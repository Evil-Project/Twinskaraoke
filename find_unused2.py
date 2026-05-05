import os
import re

swift_files = []
for root, dirs, files in os.walk('.'):
    if '.git' in root or '.build' in root or 'xcodeproj' in root:
        continue
    for f in files:
        if f.endswith('.swift'):
            swift_files.append(os.path.join(root, f))

# Search for the filename without .swift
all_content = {}
for path in swift_files:
    with open(path, 'r', encoding='utf-8') as f:
        all_content[path] = f.read()

unused_files = []
for path in swift_files:
    filename = os.path.basename(path).replace('.swift', '')
    if 'App' in filename or 'Tests' in filename or 'Models' in filename:
        continue
        
    is_used = False
    pattern = re.compile(r'\b' + filename + r'\b')
    for other_path, content in all_content.items():
        if other_path == path:
            continue
        if pattern.search(content):
            is_used = True
            break
            
    if not is_used:
        unused_files.append(path)

print("Potentially unused files based on filename:")
for f in unused_files:
    print(f)

