# Exelia OS

Systeme d'exploitation graphique pour **ComputerCraft: Tweaked** (ordinateur avance, ecran couleur, HTTP active).

## Installation (au choix)

**1. Avec l'installateur** - sur l'ordinateur :

```
wget run https://raw.githubusercontent.com/Archie442/ExeliaOS/main/install.lua
```

**2. Avec `startup.lua` seul** - telechargez `startup.lua` sur l'ordinateur (a la racine) et redemarrez (Ctrl+R) :

```
wget https://raw.githubusercontent.com/Archie442/ExeliaOS/main/startup.lua startup.lua
```

Dans les deux cas, au premier lancement `startup.lua` telecharge **tous** les fichiers du depot
(selon `manifest.json`) et les place au bon endroit, puis demarre le systeme.

## Structure

```
startup.lua                       lanceur + installation au premier lancement
install.lua                       installateur (telecharge startup.lua)
manifest.json                     liste des fichiers du systeme et version
System/config/                    configuration (config, programs, update.cfg, backup/)
System/run/main.lua               processus principal : fenetres, evenements, connexion
System/run/display.lua            affichage : fond, barre de menu, menu demarrer, notifications
System/run/ressource_loader.lua   fichiers : acces restreint a /User, programmes, ExeliaScript
System/run/fundamental_apps.lua   Terminal, Explorateur, Parametres, Mise a jour, Infos
System/IntegratedApps/*.as        App Store, Messages, Editeur, Calcul
Programs/<id>/<id>.as             programmes installes (App Store)
ProgramsData/<id>/*.dg            donnees de chaque programme (groupes de donnees)
User/Documents, User/Desktop      les seuls dossiers visibles par l'utilisateur
```

L'utilisateur (Explorateur, Terminal, Editeur, programmes) voit `/User` comme sa racine :
`System`, `Programs`, `ProgramsData` et `rom` sont inaccessibles, meme en lecture.
Les programmes installes tournent dans un bac a sable (pas de `shell`, `io`, `os.run`...).

## Mise a jour

L'application **Mise a jour** lit `manifest.json` a la racine du depot :

```json
{ "version": "4.1", "files": ["startup.lua", "System/run/main.lua", "..."] }
```

Seuls `startup.lua`, `System/run/*.lua` et `System/IntegratedApps/*.as` peuvent etre mis a jour.
Les anciens fichiers sont sauvegardes dans `System/config/backup` ; si le demarrage echoue
juste apres une mise a jour, le lanceur restaure la version precedente.
Pour publier une version : changez `VERSION` dans `startup.lua` et `version` dans `manifest.json`.

## ExeliaScript (.as)

Du Lua avec une API objet :

```lua
app = exelia.getProgram(app)
app.version = "1.0.0"
app.minOsVersion = 4.0
app.pastebin = ""                    -- mise a jour automatique de l'app
app.config.updating = "automatic"

display = app.getObject(display)     -- aussi : keyboard, mouse, timer, storage
display.window.on()
window = display.window()
window.name = "Mon app " + app.version     -- + concatene les textes
```

En-tete optionnel d'un fichier `.as` : `--@name`, `--@size 46x15`, `--@description`, `--@author`.

API systeme : `exelia.getVersion()`, `exelia.getUsername()`, `exelia.getAppList()`,
`exelia.notifyUser("Titre", "Contenu")`, `exelia.alertUser("Texte")`,
`exelia.dataGroup.create/delete/get/registerVariable/save/saveAll`.
Voir `examples/snake.as`.
