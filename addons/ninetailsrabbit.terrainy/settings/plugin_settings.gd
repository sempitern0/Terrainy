@tool
class_name MyPluginSettings extends RefCounted

const PluginPrefixName: String = "ninetailsrabbit.terrainy" ## The folder name
const GitRepositoryName: String = "terrainy"

static var PluginName: String = "Terrainy"
static var PluginProjectName: String = ProjectSettings.get_setting("application/config/name")
static var PluginBasePath: String = "res://addons/%s" % PluginPrefixName
static var PluginLocalConfigFilePath = "%s/plugin.cfg" % PluginBasePath
static var PluginSettingsBasePath: String = "%s/config/%s" % [PluginProjectName, PluginPrefixName]
static var RemoteReleasesUrl = "https://api.github.com/repos/ninetailsrabbit/%s/releases" % GitRepositoryName
static var PluginTemporaryDirectoryPath = OS.get_user_data_dir() + "/" + PluginPrefixName
static var PluginTemporaryReleaseUpdateDirectoryPath = "%s/update" % PluginTemporaryDirectoryPath
static var PluginTemporaryReleaseFilePath = "%s/%s.zip" % [PluginTemporaryDirectoryPath, PluginPrefixName]
static var PluginDebugDirectoryPath = "res://debug"

#region Plugin Settings
static var UpdateNotificationSetting: String = PluginSettingsBasePath + "/update_notification_enabled"
#endregion

## Enable to test the updater without need to have a latest release version to trigger it
static var DebugMode: bool = false

static func set_update_notification(enable: bool = true) -> void:
	ProjectSettings.set_setting(UpdateNotificationSetting, enable)
	ProjectSettings.add_property_info({
		"name": UpdateNotificationSetting,
		"type": typeof(enable),
	 	"value": enable,
		"hint": PROPERTY_HINT_TYPE_STRING,
		"hint_string": "Turn notifications on or off to receive alerts when new versions of the plugin are released"
	})
	ProjectSettings.save()


static func is_update_notification_enabled() -> bool:
	return ProjectSettings.get_setting(UpdateNotificationSetting, true)


static func remove_settings() -> void:
	remove_setting(UpdateNotificationSetting)


static func remove_setting(name: String) -> void:
	if ProjectSettings.has_setting(name):
		ProjectSettings.set_setting(name, null)
		ProjectSettings.save()
		
