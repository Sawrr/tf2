# tf2
Sourcemod plugins for Team Fortress 2

## AdvancedPause

### Description
Extension of F2's Pause plugin that automatically pauses the game when a player disconnects. Allows for players to reconnect in a similar state as when they DC'd. 

#### v1.0.1
Fixed issue where plugin did not disable after matches ending due to time limit

#### v1.0.0  
Initial upload

### Installation
Place AdvancedPause.smx in /tf/addons/sourcemod/plugins/

## GG Concede

### Description
Allows players to use !gg or /gg command to concede a match. The match will end after 10 seconds unless someone on the team enters !cancel or /cancel to stop the countdown.
Enable or disable with gg\_enabled

ConVars for customization
gg\_enabled - Sets whether calling gg is enabled.
gg\_winnerconcede - Sets whether the winning team can call gg.
gg\_winthreshold - Sets the number of round wins a team must win before their opponents may call gg.
gg\_windifference - Sets the difference in round wins required for the losing team to call gg.
gg\_timeleft - Sets the number of minutes left in the game before a team can call gg.

### Installation
Place ggconcede.smx in /tf/addons/sourcemod/plugins/

#### v1.0.0  
Initial upload

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
