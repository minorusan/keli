# GALLERY.md — Model gallery

Two browsers live in `Assets/Scripts/Gallery/`:

- **`RocketboxGalleryGUI.cs`** — the quick one. Legacy **OnGUI** (no Canvas), drag onto one
  empty GameObject, ◀/▶ buttons + path label, `Resources.Load` **by path**, `_scale` float for
  the GUI. Loads one model at a time (no LoadAll). **Use this to eyeball the Rocketbox models.**
- **`PrefabGallery.cs`** — the Canvas/TMP version (slider, folder nav). Documented below.

## RocketboxGalleryGUI (OnGUI) — quick start

1. Create an empty GameObject, add **Maradel ▸ Rocketbox Gallery (OnGUI)**.
2. Set `_resourcesFolder` (Resources-relative), e.g.
   `Microsoft-Rocketbox-master/Assets/Avatars/Adults`. Keep `_onlyFacial = true` to browse the
   **`*_facial` FBX** (the ones with viseme blendshapes).
3. Right-click the component ▸ **Scan Resources** → fills the path list from disk.
4. Press Play. ◀/▶ step models, `–/+` size the model, `_scale` (Inspector) scales the GUI.

### Rocketbox import facts (verified on disk)

- Extracted to `Assets/App/Content/Resources/Microsoft-Rocketbox-master/` (~23 GB).
- Categories: `Animals`, `Animations`, `Avatars` (Adults 40, Children 4, Professions 73 = 117
  human avatars), `Editor`.
- **Each avatar has TWO FBX**: `Name.fbx` (plain body) and **`Name_facial.fbx`** — the facial
  one carries the **15 visemes + FACS blendshapes**. Lipsync uses the `_facial` variant.
- FBX path shape: `…/Avatars/<Group>/<Name>/Export/<Name>(_facial).fbx`.
- ⚠️ `…/Assets/Editor/FixRocketboxMaxImport.cs` sits **inside Resources**. It still works as an
  editor script, but should be **moved to `Assets/Editor/`** (out of Resources) and is what
  fixes 3ds-Max→Unity materials + the humanoid rig.

---

## PrefabGallery (Canvas + TMP)

`Assets/Scripts/Gallery/PrefabGallery.cs` — browse prefabs stored under a `Resources/`
folder, show one on a stage, scale it, and step through items and folders.

## What it does

- **Instantiate mode:** the current prefab is instantiated under a *stage mount*; switching
  destroys the old instance and instantiates the next.
- **Item nav:** Left / Right buttons cycle prefabs within the current folder (wraps around).
- **Folder nav:** Folder Prev / Next buttons cycle folders; a TMP label shows
  `name (i/n)`.
- **Scale:** a Slider (0..100) maps to `minScale..maxScale` and scales the live instance; a
  TMP label shows the 0–100 value.
- **Editor scan:** right-click the component ▸ **Scan Resources Folders** fills the folder
  list from the on-disk `Resources/<resourcesRoot>` subfolders (run it after the import).

## Why folders are a serialized list

Unity's `Resources` API **cannot enumerate subfolders at runtime** — only load assets by
path. So the navigable folders are stored on the component. The Editor scan populates them
from disk; at runtime `Resources.LoadAll<GameObject>("<root>/<folder>")` loads each folder's
prefabs.

## Scene setup (once the prefabs are in Resources)

1. Put prefabs under e.g. `Assets/App/Content/Resources/Gallery/<Category>/*.prefab`.
   (`resourcesRoot` = `Gallery`; each `<Category>` becomes a navigable folder.)
2. Create a Canvas with: a Slider, Left/Right Buttons, Folder Prev/Next Buttons, and three
   `TextMeshPro - Text (UI)` labels (scale, item, folder).
3. Add an empty **Stage** GameObject where the model should appear.
4. Add `Maradel ▸ Prefab Gallery` to a GameObject and wire all references. Set `resourcesRoot`.
5. Right-click the component ▸ **Scan Resources Folders**.
6. Play. Left/Right step prefabs, Folder Prev/Next step categories, the slider scales.

## Inspector reference

| Field | Meaning |
|------|---------|
| `resourcesRoot` | Path under a `Resources/` folder (e.g. `Gallery`). Empty = the Resources root. |
| `folders` | Subfolder names (filled by the scan). |
| `stageMount` | Parent for the instantiated prefab (defaults to this transform). |
| `panelRenderer` | Optional backdrop panel MeshRenderer. |
| `scaleSlider` / `scaleLabel` | 0..100 scale control + TMP readout. |
| `minScale` / `maxScale` | World scale at slider 0 and 100. |
| `leftButton` / `rightButton` / `itemLabel` | Item cycling + TMP `name (i/n)`. |
| `folderPrevButton` / `folderNextButton` / `folderLabel` | Folder cycling + TMP label. |

## Public API (call from other code / UI events)

`LoadFolder(int)`, `NextFolder()`, `PreviousFolder()`, `Next()`, `Previous()`,
`ApplyScale()`, `CurrentFolder`, `CurrentInstance`.

## Roadmap & end goal

- **Now (this gallery):** a **5 GB+** prefab import lands in `Resources/` so we can *see and
  pick* the face models in-editor. Resources is the quick path — no extra setup.
- **Later (tablet app):** migrate to **Addressables**. A 5 GB+ `Resources/` folder is a
  non-starter for a shipped APK (everything in `Resources` is force-included, uncompressed in
  RAM at load, and bloats build time). Addressables stream models on demand and can live in
  remote/OBB content. The gallery's source loading is isolated to `LoadFolder()` /
  `Resources.LoadAll`, so swapping in an `AddressablesGallerySource` later is a localized change.
- **End goal: Maradel swaps FACES.** This gallery is how we audition the models; in the
  product, **Maradel selects/loads a face at runtime** and it becomes the talking head. That
  ties straight into the lipsync system ([LIPSYNC.md](LIPSYNC.md)): each face ships its own
  `VisemeMap` so swapping the avatar is a *data* change, not code. Picking a prefab here is
  the same act Maradel will perform programmatically later.

## Notes

- Labels use **TextMeshPro** (`TMP_Text`). Run *Window ▸ TextMeshPro ▸ Import TMP Essentials*
  once if prompted.
- Prefabs in `Resources` are always included in the build (and not stripped) — fine for a
  gallery, **bad for a 5 GB+ shipping build**. This is the temporary path; Addressables is the
  destination (see Roadmap above).
