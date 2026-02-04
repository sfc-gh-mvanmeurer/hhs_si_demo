#!/usr/bin/env python3
"""
Sample Large CMS Files for Stage Upload
========================================
Reduces large CSV files to fit within 250MB upload limit.

Files affected:
- Carrier Claims 1A (1.2GB → ~200MB)
- Carrier Claims 1B (1.2GB → ~200MB)  
- Prescription Drug Events (405MB → ~200MB)
"""

import os
import random

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'data')
OUTPUT_DIR = os.path.join(DATA_DIR, 'sampled')
RANDOM_SEED = 42
TARGET_SIZE_MB = 200  # Target ~200MB to stay well under 250MB limit

def sample_csv_file(input_path, output_path, sample_rate):
    """Sample a CSV file by keeping header + random sample of rows."""
    random.seed(RANDOM_SEED)
    
    print(f"  Reading: {os.path.basename(input_path)}")
    
    with open(input_path, 'r') as infile:
        header = infile.readline()
        lines = infile.readlines()
    
    original_count = len(lines)
    sample_size = int(original_count * sample_rate)
    
    print(f"  Original rows: {original_count:,}")
    print(f"  Sampling {sample_rate*100:.0f}% → {sample_size:,} rows")
    
    sampled_lines = random.sample(lines, sample_size)
    
    with open(output_path, 'w') as outfile:
        outfile.write(header)
        outfile.writelines(sampled_lines)
    
    output_size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"  Output size: {output_size_mb:.1f} MB")
    print(f"  Saved: {os.path.basename(output_path)}")
    
    return sample_size

def main():
    print("=" * 60)
    print("Sampling Large CMS Files for Stage Upload")
    print("=" * 60)
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Files to sample with their approximate sample rates to hit ~200MB
    files_to_sample = [
        {
            'input': 'DE1_0_2008_to_2010_Carrier_Claims_Sample_1A.csv',
            'output': 'Carrier_Claims_Sample_1A_sampled.csv',
            'sample_rate': 0.15  # 1.2GB * 0.15 ≈ 180MB
        },
        {
            'input': 'DE1_0_2008_to_2010_Carrier_Claims_Sample_1B.csv',
            'output': 'Carrier_Claims_Sample_1B_sampled.csv',
            'sample_rate': 0.15
        },
        {
            'input': 'DE1_0_2008_to_2010_Prescription_Drug_Events_Sample_1.csv',
            'output': 'Prescription_Drug_Events_sampled.csv',
            'sample_rate': 0.45  # 405MB * 0.45 ≈ 180MB
        }
    ]
    
    total_rows = 0
    
    for file_info in files_to_sample:
        input_path = os.path.join(DATA_DIR, file_info['input'])
        output_path = os.path.join(OUTPUT_DIR, file_info['output'])
        
        if not os.path.exists(input_path):
            print(f"\n⚠️  Skipping (not found): {file_info['input']}")
            continue
        
        print(f"\nProcessing: {file_info['input']}")
        rows = sample_csv_file(input_path, output_path, file_info['sample_rate'])
        total_rows += rows
    
    print("\n" + "=" * 60)
    print("Sampling complete!")
    print("=" * 60)
    print(f"\nSampled files saved to: data/sampled/")
    print(f"Total sampled rows: {total_rows:,}")
    
    # Show final file sizes
    print("\nFinal file sizes:")
    for f in os.listdir(OUTPUT_DIR):
        if f.endswith('.csv'):
            size_mb = os.path.getsize(os.path.join(OUTPUT_DIR, f)) / (1024 * 1024)
            print(f"  {f}: {size_mb:.1f} MB")
    
    print("\n📁 Files to upload to Snowflake stage:")
    print("   @HHS_DATA_STAGE/cms/  ← Original small files + sampled large files")
    print("   @HHS_DATA_STAGE/prepared/ ← Fraud simulation files")

if __name__ == "__main__":
    main()
