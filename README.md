## 🧬 16S rRNA Habitat Prediction Pipeline

This repository contains two Bash scripts for automated **16S rRNA amplicon processing** and **Large Language Model (LLM)–based microbial habitat prediction**.  
The workflow is designed for **HPC environments** (e.g., UF HiPerGator) and integrates *Nextflow* (`epi2me-labs/wf-16s`) with **Meta-Llama-3-8B-Instruct** for downstream ecological annotation.

---

## 📁 Repository Contents

| File | Description |
|------|--------------|
| **`run_16s_pipeline.sh`** | Converts `.bam` files to `.fastq`, filters reads, and performs 16S taxonomic classification using Nextflow. |
| **`batch_predict_habitat_Q1_Github.sh`** | Runs large-scale habitat prediction from 16S taxonomy tables using a fine-tuned LLM. |

---

## ⚙️ Requirements

### **Modules (HiPerGator or similar HPC)**
```
module load samtools nanofilt nextflow singularity pytorch/2.7
```

### **Environment Variables**
| Variable | Description |
|-----------|--------------|
| `BASE_DIR` | Base directory containing demultiplexed `.bam` files |
| `HF_HOME`, `TRANSFORMERS_CACHE` | Cache directory for Hugging Face models |
| `HUGGING_FACE_HUB_TOKEN` | Hugging Face access token for Meta-Llama model |
| `PYTHON_EXEC` | Python path within the LLM environment (e.g., llama-env/bin/python) |

### **Python dependencies** (inside `llama-env`)
```bash
pip install torch transformers
```

---

## 🧬 Workflow Overview

### **Step 1 – 16S rRNA Processing (`run_16s_pipeline.sh`)**
1. Converts `.bam` → `.fastq` using **samtools**.  
2. Filters reads using **NanoFilt** (`-q 20 -l 100`).  
3. Runs **Nextflow** workflow `epi2me-labs/wf-16s` for taxonomic classification.  
4. Outputs per-barcode species abundance tables.

### **Step 2 – LLM-based Habitat Prediction (`batch_predict_habitat_Q1_Github.sh`)**
1. Reads each `abundance_table_species.tsv`.  
2. Fetches corresponding **NCBI BioSample XML** via `esearch`/`efetch`.  
3. Extracts relevant metadata (e.g., `geo_loc_name`, `isolation_source`).  
4. Prompts **Meta-Llama-3-8B-Instruct** to infer a concise habitat label:
   ```
   Marine, Terrestrial, Wastewater, or Insufficient
   ```
5. Saves the result to `habitats/` directory as a TSV file.

---

## 🚀 QuickStart Example

### **Input:**
Example 16S result file (`abundance_table_species.tsv`)
```
Taxonomy	Sample	Abundance
Flavobacterium stagni	Filtered_CLEW8	0.052
Paracoccus denitrificans	Filtered_CLEW8	0.028
Pseudomonas aeruginosa	Filtered_CLEW8	0.013
```

### **Step 1: Run the 16S pipeline**
```bash
bash run_16s_pipeline.sh
```

### **Step 2: Predict microbial habitats**
```bash
bash batch_predict_habitat_Q1_Github.sh
```

### **Output (example `Filtered_CLEW8_habitat.tsv`):**
```
Taxon	Abundance	Habitat	Metadata
Flavobacterium stagni	0.052	Freshwater	Taiwan; pond water
Paracoccus denitrificans	0.028	Wastewater	activated sludge; aeration tank
Pseudomonas aeruginosa	0.013	Terrestrial	soil; hospital environment
```

---

## 🗂️ Output Structure

```
16s_pipeline/
 ├── demux/
 ├── fastq_outputs/
 ├── filtered_fastqs/
 ├── wf16s_results/
 │    ├── barcode01/
 │    │     └── output/abundance_table_species.tsv
 │    └── barcode02/...
 ├── habitat_xmls/
 └── habitats/
       ├── barcode01_habitat.tsv
       └── barcode02_habitat.tsv
```

---

## 💡 Notes

- Each barcode is processed independently for scalability.  
- Existing XML metadata are reused to avoid redundant downloads.  
- Model prompts are truncated at 7900 tokens to prevent GPU overflow.  
- The script outputs:
  - `"insufficient"` → not enough metadata  
  - `"unknown"` → metadata fallback  
  - `"NA"` → malformed LLM output  

---

## 🧠 Citation

If you use this workflow, please cite:
- **epi2me-labs/wf-16s** – Oxford Nanopore Technologies (for 16S analysis)  
- **Meta-Llama-3-8B-Instruct**, Meta AI (2024) – for habitat inference  

---

## ✉️ Contact  
**Maintainer:** Chamteut Oh (University of Florida)  
📧 [chamteutoh@ufl.edu]
