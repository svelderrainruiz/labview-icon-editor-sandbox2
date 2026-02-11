# Manual Setup & Editing Instructions

This document provides **manual** steps to configure, edit, and distribute the LabVIEW Icon Editor source code without using PowerShell automation.

---

## Table of Contents

1. [Compatible LabVIEW Versions](#compatible-labview-versions)
2. [Editing Guide (Manual)](#editing-guide-manual)
3. [Distribution Guide (Manual)](#distribution-guide-manual)
4. [Restore LabVIEW Environment](#restore-environment)

---

<a name="compatible-labview-versions"></a>
## 1. Compatible LabVIEW Versions

- Source is saved in **LabVIEW 2021 (21.0)** format.  
- Both **LabVIEW 2021 (21.0), 32-bit and 64-bit** are typically required if you plan to build or distribute for both architectures.
- Editing can be done on any LabVIEW version that can preserve the **2021** file format.

---

<a name="editing-guide-manual"></a>
## 2. Editing Guide (Manual)

1. **Clone** this repository to a development location, for example:

   ```
   C:\labview-icon-editor
   ```

2. **Run** the following VI to point the launcher to source:

   ```
   Tooling\Set Run Icon Editor from Source.vi
   ```

   This VI will:
   - Configure the Icon Editor launcher path to your repository source location.
   - Route Icon Editor launches through the source tree while you edit.

3. **Open** the project file:

   ```
   lv_icon_editor.lvproj
   ```

4. **Locate** the top-level VI inside the project:

   ```
   My Computer » resource/plugins » lv_icon.lvlib » lv_icon.vi
   ```

   You can now edit and develop the Icon Editor as needed.

---

<a name="distribution-guide-manual"></a>
## 3. Distribution Guide (Manual)

To **manually distribute** your custom Icon Editor:

1. **Build** the Packed Project Library (or .lvlibp):
   - In LabVIEW, compile your top-level `lv_icon.lvlib` into a `.lvlibp` for deployment.

2. **On the target machine**:
   - Rename the default:

     ```
     <LabVIEW>\resource\plugins\lv_icon.lvlibp
     ```
     to:
     ```
     lv_icon.lvlibp.ship
     ```
   - Similarly archive or rename:
     ```
     <LabVIEW>\vi.lib\LabVIEW Icon API
     ```
   - **Copy** your newly built `lv_icon.lvlibp` and `vi.lib\LabVIEW Icon API\*` into the corresponding LabVIEW folders on the target machine.

   You now have a custom, manually distributed Icon Editor that can support any LabVIEW version available up until the creation of this document.

---

<a name="restore-environment"></a>
## 4. Restore LabVIEW Environment

When you're finished developing or distributing, you can return LabVIEW to its default state:

1. **Run**:
   ```
   Tooling\Unset Run Icon Editor from Source.vi
   ```
2. **If you manually replaced install files**, restore them:
   - Rename backup `lv_icon.lvlibp.ship` back to `lv_icon.lvlibp` (or reinstall the original file).
   - Restore `<LabVIEW>\vi.lib\LabVIEW Icon API` from your archived copy or installation source.
3. **Restart LabVIEW** to confirm the built-in Icon Editor loads correctly.
