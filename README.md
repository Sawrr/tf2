# tf2
Sourcemod plugins for Team Fortress 2

TeamPrefixes

v1.0
Initial upload
v1.1
Applies prefix to players after they manually change their name
Added sm_teamprefixes_mapchange_disabled convar to disable plugin on map change

Known bugs:
SOAPDM + Reserved slots plugin: when soap_tournament detects the round start, it executes tf/cfg/sourcemod/soap_live.cfg which unloads a number of plugins. If reservedslots is unloaded, the cvar sm_teamprefixes_enabled will be set to 0. To fix this, comment out the line like so: //sm plugins unload reservedslots