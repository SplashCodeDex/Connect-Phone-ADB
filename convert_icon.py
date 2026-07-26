from PIL import Image
img = Image.open(r"C:\Users\NicoDex\.gemini\antigravity-cli\brain\2e07987f-a127-46e0-95e9-65e358d7b8a5\adb_connect_app_icon_1784852546657.jpg")
# Ensure image is square and save as multi-size ICO
img.save(r"C:\Users\NicoDex\Connect-Phone-ADB\assets\app-icon.ico", format="ICO", sizes=[(256, 256), (128, 128), (64, 64), (32, 32), (16, 16)])
