import os
import re

useless_patterns = [
    r"^\s*// Write your test here and use APIs.*?\n",
    r"^\s*// Swift Testing Documentation.*?\n",
    r"^\s*// https://developer\.apple\.com/documentation/testing.*?\n",
    r"^\s*// Insert steps here to perform after app launch.*?\n",
    r"^\s*// such as logging into a test account.*?\n",
    r"^\s*// XCUIAutomation Documentation.*?\n",
    r"^\s*// https://developer\.apple\.com/documentation/xcuiautomation.*?\n",
    r"^\s*// Put setup code here\..*?\n",
    r"^\s*// In UI tests it is usually best to stop immediately.*?\n",
    r"^\s*// In UI tests it’s important to set the initial state.*?\n",
    r"^\s*// Put teardown code here\..*?\n",
    r"^\s*// UI tests must launch the application that they test\..*?\n",
    r"^\s*// Use XCTAssert and related functions.*?\n",
    r"^\s*// This measures how long it takes to launch your application\..*?\n",
]

for target in ["TwinskaraokeTests", "TwinskaraokeUITests", "TwinskaraokeWatchAppTests", "TwinskaraokeWatchAppUITests"]:
    if not os.path.exists(target):
        continue
    for root, dirs, files in os.walk(target):
        for file in files:
            if file.endswith(".swift"):
                path = os.path.join(root, file)
                with open(path, "r", encoding="utf-8") as f:
                    content = f.read()
                
                original_content = content
                for pattern in useless_patterns:
                    content = re.sub(pattern, "", content, flags=re.MULTILINE)
                
                if content != original_content:
                    with open(path, "w", encoding="utf-8") as f:
                        f.write(content)
