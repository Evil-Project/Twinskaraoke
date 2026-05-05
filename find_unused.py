import os
import re

swift_files = []
for root, dirs, files in os.walk('.'):
    if '.git' in root or '.build' in root or 'xcodeproj' in root:
        continue
    for f in files:
        if f.endswith('.swift'):
            swift_files.append(os.path.join(root, f))

# Find all types declared in each file
file_types = {}
decl_pattern = re.compile(r'(?:class|struct|enum|protocol)\s+([A-Za-z0-9_]+)')

all_content = {}
for path in swift_files:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
        all_content[path] = content
        types = decl_pattern.findall(content)
        file_types[path] = types

unused_files = []

for path, types in file_types.items():
    if len(types) == 0:
        continue
        
    is_used = False
    # If it's an app entry point or tests, we skip
    if 'App.swift' in path or 'Tests' in path:
        continue
        
    for t in types:
        # Check if type 't' is used in any OTHER file
        type_used = False
        pattern = re.compile(r'\b' + t + r'\b')
        for other_path, content in all_content.items():
            if other_path == path:
                continue
            if pattern.search(content):
                type_used = True
                break
        
        if type_used:
            is_used = True
            break
            
    if not is_used:
        unused_files.append(path)

print("Potentially unused files based on types:")
for f in unused_files:
    print(f)

