class_name AdMobProvider
extends AdProvider

## AdMob rewarded-ads implementation (godot-admob plugin, GMA SDK).
## Emits EXACTLY ONE of rewarded_earned / ad_failed per show_rewarded() call.

const TEST_REWARDED_ANDROID := "ca-app-pub-3940256099942544/5224354917"
const TEST_REWARDED_IOS := "ca-app-pub-3940256099942544/1712485313"
const REAL_REWARDED_ANDROID := ""   # TODO: paste real Android rewarded unit ID at release
const REAL_REWARDED_IOS := ""       # TODO: paste real iOS rewarded unit ID at release
const IS_REAL := false              # flip to true at release (also set real App ID in Project Settings -> admob/general/android/app_id)
const TEST_MODE := true             # simulate rewarded ads on non-mobile dev machines; set false for release
const TEST_SIMULATE_FAILURE := false  # when TEST_MODE, emit ad_failed instead of rewarded_earned (tests the retry path)

var _rewarded_ad: RewardedAd = null
var _rewarded_loader := RewardedAdLoader.new()
var _is_mobile: bool = false
var _initialized: bool = false
var _reward_pending: bool = false


func _ready() -> void:
	_is_mobile = OS.get_name() == "Android" or OS.get_name() == "iOS"
	if not _is_mobile:
		print("AdMobProvider: non-mobile platform detected — ad initialization skipped.")
		return
	request_user_consent()


func is_supported() -> bool:
	return _is_mobile or TEST_MODE


# --- Consent + initialization (UMF v2 flow, adapted to godot-admob v5.0.0 API) ---

func request_user_consent() -> void:
	var params := ConsentRequestParameters.new()
	UserMessagingPlatform.consent_information.update(
		params, _on_consent_info_update_success, _on_consent_info_update_failure
	)


func _on_consent_info_update_success() -> void:
	if UserMessagingPlatform.consent_information.get_is_consent_form_available():
		load_and_show_form()
	else:
		initialize_ads()


func _on_consent_info_update_failure(_error: FormError) -> void:
	initialize_ads()


func load_and_show_form() -> void:
	UserMessagingPlatform.load_consent_form(_on_consent_form_loaded, _on_consent_form_load_failed)


func _on_consent_form_loaded(consent_form: ConsentForm) -> void:
	consent_form.show(_on_consent_form_dismissed)


func _on_consent_form_load_failed(_error: FormError) -> void:
	initialize_ads()


func _on_consent_form_dismissed(_error: FormError) -> void:
	initialize_ads()


func initialize_ads() -> void:
	var on_init_listener := OnInitializationCompleteListener.new()
	on_init_listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
		_initialized = true
		_load_rewarded()
	var request_config := RequestConfiguration.new()
	MobileAds.set_request_configuration(request_config)
	MobileAds.initialize(on_init_listener)


# --- Rewarded ad lifecycle ---

func _current_rewarded_unit_id() -> String:
	if IS_REAL:
		return REAL_REWARDED_IOS if OS.get_name() == "iOS" else REAL_REWARDED_ANDROID
	return TEST_REWARDED_IOS if OS.get_name() == "iOS" else TEST_REWARDED_ANDROID


func _load_rewarded() -> void:
	if not _initialized:
		return
	var ad_unit_id := _current_rewarded_unit_id()
	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: RewardedAd) -> void:
		_rewarded_ad = ad
		_setup_rewarded_callbacks()
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		printerr("AdMobProvider: rewarded ad failed to load: ", error.message)
		_rewarded_ad = null
	_rewarded_loader.load(ad_unit_id, AdRequest.new(), callback)


func _setup_rewarded_callbacks() -> void:
	if not _rewarded_ad:
		return
	var callbacks := FullScreenContentCallback.new()
	callbacks.on_ad_dismissed_full_screen_content = func() -> void:
		_rewarded_ad.destroy()
		_rewarded_ad = null
		_load_rewarded()
		var earned: bool = _reward_pending
		_reward_pending = false
		if earned:
			rewarded_earned.emit()
		else:
			ad_failed.emit()
	callbacks.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void:
		_rewarded_ad.destroy()
		_rewarded_ad = null
		_load_rewarded()
		_reward_pending = false
		ad_failed.emit()
	_rewarded_ad.full_screen_content_callback = callbacks


func show_rewarded() -> void:
	if TEST_MODE:
		_simulate_reward()
		return
	if not _is_mobile:
		ad_failed.emit()
		return
	if _rewarded_ad == null:
		ad_failed.emit()
		_load_rewarded()
		return
	var reward_listener := OnUserEarnedRewardListener.new()
	reward_listener.on_user_earned_reward = func(_item: RewardedItem) -> void:
		_reward_pending = true
	_rewarded_ad.show(reward_listener)


## Test-mode helper: pretends an ad played and the reward was granted
## (or failed, if TEST_SIMULATE_FAILURE). Lets devs test the wheel flow
## on machines without the AdMob native plugin.
func _simulate_reward() -> void:
	await get_tree().create_timer(1.5).timeout
	if TEST_SIMULATE_FAILURE:
		ad_failed.emit()
	else:
		rewarded_earned.emit()