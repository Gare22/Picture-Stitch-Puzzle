class_name WebAdProvider
extends AdProvider

## Web placeholder for rewarded ads that does not rely on Google.
## Configure ads/web_simulate_rewarded (Project Settings):
##   true  — "earn" the reward instantly (personal project / no ad network yet)
##   false — emit ad_failed with a hint; wire a real web ad network here later
##           (the interface makes swapping one in a one-file change).


func is_supported() -> bool:
	return true


func show_rewarded() -> void:
	if ProjectSettings.get_setting("ads/web_simulate_rewarded", true):
		await get_tree().create_timer(1.2).timeout
		rewarded_earned.emit()
	else:
		printerr("WebAdProvider: no web ad network configured — wire one in this file.")
		ad_failed.emit()