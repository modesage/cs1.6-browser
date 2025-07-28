# Counter-Strike 1.6 - Browser Edition

This project allows you to play **Counter-Strike 1.6 directly in your browser** using the [Xash3D FWGS engine](https://github.com/FWGS/xash3d-fwgs), compiled to WebAssembly by [WebXash3D-FWGS](https://github.com/yohimik/webxash3d-fwgs).  

---

## **Project Structure**

````bash
├── get_cs_assets
    ├── cs  # CS 1.6 installation directory
        .         
        ├── cstrike
        └── valve
    ├── steamcmd   # SteamCMD installation directory
    ├── download-assets-linux.sh   # Linux/Mac asset downloader    
    └── download-assets-win.bat  # Windows asset downloader 
    
├── index.html     # Main game page
├── README.md
└── valve.zip      # Game assets       
````

---

## **Getting Started**

### **1. Download Game Assets**

#### **Windows**

1. Run the `download-assets-win.bat` file:

   ```bash
   download-assets-win.bat
   ```

   This will:

   - Install **SteamCMD** if not already installed.
   - Download **Counter-Strike 1.6 assets**.
   - Save them inside a `cs` folder.

2. Zip the `cstrike` and `valve` folders into a single `valve.zip` file.

#### **Linux/Mac**

1. Make the script executable:

   ```bash
   chmod +x download-assets-linux.sh
   ```

2. Run it:

   ```bash
   ./download-assets-linux.sh
   ```

3. Once downloaded, zip the `cstrike` and `valve` folders:

   ```bash
   zip -r ../valve.zip ./cs/cstrike ./cs/valve
   ```

---

### **2. Place Files**

- Ensure the `valve.zip` file is in the **same directory as `index.html`**.

---

### **3. Run a Local Web Server of your choice**

In this case we are using [Node.js](https://nodejs.org/en/download), make sure you have it installed on your computer.

The [**serve**](https://www.npmjs.com/package/serve) package will be used to serve the entire current folder over HTTP on your local network (intranet).

```bash
npx serve -p 8080 
```

If you want to restrict and have it accessible only on your computer (localhost) you can use the following command:

```bash
npx serve -p 8080 -l 127.0.0.1
```

---

### **4. Play the Game**

1. Open your browser and go to:

   ```bash
   http://localhost:8080
   ```

2. Wait for the assets to load.
3. Click **"Go Fullscreen"** when ready.
4. Enjoy **Counter-Strike 1.6 in your browser!**

---

**Note:** The CS 1.6 assets are not included in this project. Users must provide their own legally-owned copy of the game. This project is for non-commercial, non-profit purposes only.

---
