#!/bin/bash

# === ENVIRONMENT SETUP ===
module load pytorch/2.7
export HF_HOME="/blue/chamteutoh/huggingface"
export TRANSFORMERS_CACHE="/blue/chamteutoh/huggingface"
export HUGGING_FACE_HUB_TOKEN=""

# === PATH CONFIGURATION ===
BASE_DIR="/blue/chamteutoh/Milton/water/16s/wf16s_results"
HABITAT_DIR="/blue/chamteutoh/Milton/water/16s/habitats"
XML_DIR="/blue/chamteutoh/Milton/plastic/habitat_xmls"
MODEL_NAME="meta-llama/Meta-Llama-3-8B-Instruct"
PYTHON_EXEC=$"/blue/chamteutoh/envs/llama-env/bin/python"

mkdir -p "$HABITAT_DIR" "$XML_DIR"

# === LOOP THROUGH ALL BARCODE FOLDERS ===
for folder in "${BASE_DIR}"/barcode*/; do
    INPUT_FILE="${folder}/output/abundance_table_species.tsv"
    if [[ ! -f "$INPUT_FILE" ]]; then
        echo "❌ Skipped: $INPUT_FILE not found."
        continue
    fi

    SAMPLE_NAME=$(basename "$folder")
    OUTPUT_FILE="${HABITAT_DIR}/${SAMPLE_NAME}_habitat.tsv"
    echo -e "Taxon\tAbundance\tHabitat\tMetadata" > "$OUTPUT_FILE"

    echo "🔄 Processing $SAMPLE_NAME..."

    dos2unix "$INPUT_FILE" 2>/dev/null

    # === FETCH XMLs ===
    mapfile -t SPECIES_LIST < <(tail -n +2 "$INPUT_FILE" | cut -f1 | awk -F';' '{print $NF}' | sort -u)

    for species_raw in "${SPECIES_LIST[@]}"; do
        species_query=$(echo "$species_raw" | sed 's/^ *//;s/ *$//')
        species_file=$(echo "$species_query" | tr ' /' '__')
        xml_file="${XML_DIR}/${species_file}.xml"

        if [[ -s "$xml_file" ]]; then
            echo "⏩ Skipped: XML exists for $species_query"
            continue
        fi

        echo "📥 Fetching XML for: $species_query"
        xml_content=$(esearch -db biosample -query "${species_query}[Organism]" | efetch -format xml)

        if [[ -n "$xml_content" && "$xml_content" == *"<BioSampleSet>"* ]]; then
            echo "$xml_content" > "$xml_file"
            echo "✅ Saved: $xml_file"
        else
            echo "<BioSampleSet></BioSampleSet>" > "$xml_file"
            echo "⚠️  Empty XML saved for: $species_query"
        fi

        sleep 1
    done

    # === INFERENCE ===
    tail -n +2 "$INPUT_FILE" | while IFS=$'\t' read -r tax sample abundance; do
        IFS=';' read -ra parts <<< "$tax"
        query="${parts[-1]}"
        query=$(echo "$query" | sed 's/^ *//;s/ *$//')
        xml_file="${XML_DIR}/$(echo "$query" | tr ' /' '__').xml"

        if [[ ! -s "$xml_file" || "$(grep -c '<BioSample' "$xml_file")" -eq 0 ]]; then
            echo -e "${query}\t${abundance}\tunknown\tunknown" >> "$OUTPUT_FILE"
            continue
        fi

        result=$("$PYTHON_EXEC" - <<EOF
from transformers import AutoTokenizer, AutoModelForCausalLM
import xml.etree.ElementTree as ET
import torch, os, re

model_name = "${MODEL_NAME}"
token = os.environ.get("HUGGING_FACE_HUB_TOKEN")
device = "cuda" if torch.cuda.is_available() else "cpu"

def extract_metadata(path):
    try:
        tree = ET.parse(path)
        root = tree.getroot()
        tags = [
            "isolation_source", "host", "broad-scale environmental context",
            "environmental medium", "sample_type", "metagenomic source", "local environmental context"
        ]
        found = set()
        attrib_keys = ["attribute_name", "harmonized_name", "display_name"]

        for biosample in root.findall(".//BioSample"):
            for attribute in biosample.findall(".//Attribute"):
                if any(attribute.attrib.get(k) in tags for k in attrib_keys):
                    val = attribute.text.strip() if attribute.text else ""
                    if val:
                        found.add(val)
        return "; ".join(found) if found else "unknown"
    except Exception:
        return "unknown"

metadata = extract_metadata("${xml_file}")
if metadata == "unknown":
    print("unknown\tunknown")
    exit(0)

prompt = f"""You are an environmental ecologist. Each keyword listed below (separated by semicolons) represents a value related to one of the following categories: isolation source, host, broad-scale environmental context, environmental medium, sample type, metagenomic source, or local environmental context. Based solely on this information (without relying on any prior knowledge), if this microbial species is detected in an environmental sample, what is the most likely environment where it is found? If any keywords are related to marine animals, consider them as indicators of a marine environment. If any keywords are related to humans, sludge, WWTP or hospitals, consider them as indicators of a wastewater environment. Choose only one of the following: Marine, Terrestrial, Wastewater, or Insufficient. Only respond with the one-word answer after 'Answer:' and nothing else.\n\nKeywords: {metadata}\nAnswer:"""

reserved_tokens = 100
max_total_tokens = 7900
tokenizer = AutoTokenizer.from_pretrained(model_name, token=token)
tokens = tokenizer.encode(prompt, add_special_tokens=False)
if len(tokens) > (max_total_tokens - reserved_tokens):
    tokens = tokens[:max_total_tokens - reserved_tokens]
prompt = tokenizer.decode(tokens, skip_special_tokens=True)

model = AutoModelForCausalLM.from_pretrained(model_name, device_map="auto", torch_dtype=torch.float16, token=token)
input_ids = tokenizer(prompt, return_tensors="pt").to(device)
outputs = model.generate(**input_ids, max_new_tokens=20)

output_ids = outputs[0][input_ids['input_ids'].shape[-1]:]
decoded = tokenizer.decode(output_ids, skip_special_tokens=True).strip()
first_word = re.findall(r"\\b\\w+\\b", decoded)[0] if decoded else "unknown"
print(f"{first_word}\t{metadata}")
EOF
        )

        habitat_only=$(echo "$result" | cut -f1)
        metadata_only=$(echo "$result" | cut -f2-)
        echo -e "${query}\t${abundance}\t${habitat_only}\t${metadata_only}" >> "$OUTPUT_FILE"
    done

    echo "✅ Finished $SAMPLE_NAME → Output saved to: $OUTPUT_FILE"
done

echo "🎉 All barcodes processed. Outputs are in: $HABITAT_DIR"
