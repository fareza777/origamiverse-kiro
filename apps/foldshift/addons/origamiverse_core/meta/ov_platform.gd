class_name OVPlatform
extends RefCounted
## Store, share and link helpers. Everything degrades gracefully offline or off Android.

const DEVELOPER_PAGE: String = "https://play.google.com/store/apps/developer?id=F7+Developer"


static func package_name() -> String:
	var id: String = str(ProjectSettings.get_setting("application/config/package_name", ""))
	return id


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "1.0.0"))


static func store_url(package: String) -> String:
	return "https://play.google.com/store/apps/details?id=" + package


## Opens the Play Store page so the player can rate the app. Returns false if nothing could be opened.
static func open_store_page(package: String) -> bool:
	if OS.get_name() == "Android" and OS.shell_open("market://details?id=" + package) == OK:
		return true
	return OS.shell_open(store_url(package)) == OK


static func open_url(url: String) -> bool:
	return OS.shell_open(url) == OK


## Opens the Android share sheet with `text`. Falls back to copying it to the clipboard.
## Returns "shared" or "copied".
static func share_text(text: String, title: String = "Share") -> String:
	if OS.get_name() == "Android" and Engine.has_singleton("AndroidRuntime"):
		var runtime: Object = Engine.get_singleton("AndroidRuntime")
		var activity: Object = runtime.call("getActivity")
		var intent_class: Object = JavaClassWrapper.wrap("android.content.Intent")
		if activity != null and intent_class != null:
			var send: Object = intent_class.call("Intent", "android.intent.action.SEND")
			if send != null:
				send.call("setType", "text/plain")
				send.call("putExtra", "android.intent.extra.TEXT", text)
				var chooser: Object = intent_class.call("createChooser", send, title)
				if chooser != null:
					activity.call("startActivity", chooser)
					return "shared"
	DisplayServer.clipboard_set(text)
	return "copied"
