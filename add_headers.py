import os
import glob
from datetime import datetime

header_template = """//
//  {filename}
//  {target}
//
//  Created by xiaoyuan on 2026/4/26.
//
"""

for target in ["Twinskaraoke", "TwinskaraokeWatchApp", "TwinskaraokeTests", "TwinskaraokeUITests", "TwinskaraokeWatchAppTests", "TwinskaraokeWatchAppUITests"]:
    if not os.path.exists(target):
        continue
    for root, dirs, files in os.walk(target):
        for file in files:
            if file.endswith(".swift"):
                path = os.path.join(root, file)
                with open(path, "r", encoding="utf-8") as f:
                    content = f.read()
                if not content.startswith("//\n//"):
                    header = header_template.format(filename=file, target=target)
                    with open(path, "w", encoding="utf-8") as f:
                        f.write(header + content)

