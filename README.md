# tasmota-custom-scripts
Scripts and Berry scripts for Tasmota

##How to automatically startup a Berry script in Tasmota?
First Upload .be file with "Manage File System" in consoles
Then if Rules enabled, enter this commans to console to autostart teams_webhook.be:
```
Rule1 ON System#Boot DO br load('teams_webhook.be') ENDON
Rule1 1
```

Else if Scripts enabled, create this script to autostart teams_webhook.be:
```
>D

>BS
=>br load("teams_webhook.be")
```
