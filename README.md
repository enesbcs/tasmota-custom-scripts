# tasmota-custom-scripts
Scripts and Berry scripts for Tasmota

## How to automatically startup a Berry script in Tasmota?
First Upload .be file with "Manage File System" in consoles
Then if Rules enabled, enter this commands to console to autostart teams_webhook.be:
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
## How to use teams_webhook.be?
1. Add an Incoming Webhook to a Teams group, and copy the whole HTTPS address
2. Open teams_webhook.be with an editor
3. Write your own HTTPS address from above to the "wurl" variable
4. Modify "return sensors['ESP32']['Temperature']" based on your own SENSORS json reported by Tasmota
5. Upload the code and run
