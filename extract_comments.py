import os
import re

for root, _, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
                for i, line in enumerate(lines):
                    if '//' in line and not line.strip().startswith('// ignore'):
                        print(f"{path}:{i+1}:{line.strip()}")
