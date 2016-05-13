# tf2
Sourcemod plugins for Team Fortress 2

## TeamPrefixes

### Description
Allows players to add a prefix / clan tag to all members of your team using /prefix [tag]  
Clear prefix with /prefix   
Enable / disable with sm\_teamprefixes_enabled  
Plugin may be disabled on map change with sm\_teamprefixes\_mapchange\_disabled

#### v1.0  
Initial upload
  
#### v1.1  
Applies prefix to players after they manually change their name  
Added sm\_teamprefixes\_mapchange\_disabled convar to disable plugin on map change
  
### Known bugs
SOAPDM + Reserved slots plugin:  
when soap\_tournament detects the round start, it executes tf/cfg/sourcemod/soap\_live.cfg which unloads a number of plugins. If reservedslots is unloaded, the cvar sm\_teamprefixes\_enabled will be set to 0. To fix this, comment out the line:  

//sm plugins unload reservedslots

### Installation
Place TeamPrefixes.smx in /tf/addons/sourcemod/plugins/

## JohnCena

### Description

Use sm_jc to surprise your friends with John Cena. Players must have the custom files downloaded for the effect to work.  

Remember, with great power comes great responsibility.

#### v1.0
Initial upload

### Installation
Place JohnCena.smx in /tf/addons/sourcemod/plugins/  
Add jc.mp3, jcm.vtf, jcm.vmt to your server in the following locations:

tf/materials/custom/jc.vtf  
tf/materials/custom/jc.vmt  
tf/sound/custom/jc.mp3  

Use sm_downloader plugin to allow players to download these files