import os
import re

header_regex = re.compile(r"^\s*//\n//\s+.*?\.swift\n//\s+.*?\n//\n//\s+Created by.*?\n//\n", re.MULTILINE)

for target in ["Twinskaraoke", "TwinskaraokeWatchApp", "TwinskaraokeTests", "TwinskaraokeUITests", "TwinskaraokeWatchAppTests", "TwinskaraokeWatchAppUITests"]:
    if not os.path.exists(target):
        continue
    for root, dirs, files in os.walk(target):
        for file in files:
            if file.endswith(".swift"):
                path = os.path.join(root, file)
                with open(path, "r", encoding="utf-8") as f:
                    content = f.read()
                
                match = header_regex.search(content)
                if match:
                    header = match.group(0)
                    content = content[:match.start()] + content[match.end():]
                    content = header + content.lstrip()
                    with open(path, "w", encoding="utf-8") as f:
                        f.write(content)
