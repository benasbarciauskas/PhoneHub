import Foundation

public func phoneControlTools(serverName: String) -> [LLMToolDefinition] {
    let specifications: [(String, String, [String: Any], [String])] = [
        ("launch_app", "Launch an app by its visible name.", [
            "app_name": ["type": "string", "description": "Visible app name"]
        ], ["app_name"]),
        ("tap", "Tap screen coordinates.", [
            "x": ["type": "number"], "y": ["type": "number"]
        ], ["x", "y"]),
        ("type_text", "Type text into the focused field.", [
            "text": ["type": "string"]
        ], ["text"]),
        ("swipe", "Swipe in a direction.", [
            "direction": ["type": "string", "enum": ["up", "down", "left", "right"]]
        ], ["direction"]),
        ("press_home", "Press the Home control.", [:], []),
        ("press_back", "Press the Back control.", [:], []),
        ("press_app_switcher", "Open the app switcher.", [:], []),
        ("scroll_to", "Scroll until visible text is found.", [
            "text": ["type": "string"],
            "direction": ["type": "string", "enum": ["up", "down"]]
        ], ["text", "direction"]),
        ("describe_screen", "Describe visible screen elements.", [:], []),
        ("open_url", "Open an HTTP or HTTPS URL.", [
            "url": ["type": "string", "format": "uri"]
        ], ["url"])
    ]

    return specifications.map { name, description, baseProperties, baseRequired in
        var properties = baseProperties
        var required = baseRequired
        if serverName == "androir" {
            properties["serial"] = ["type": "string", "description": "Android device serial"]
            required.append("serial")
        }
        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false
        ]
        let data = try! JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        return LLMToolDefinition(
            name: name,
            description: description,
            parametersJSON: String(decoding: data, as: UTF8.self)
        )
    }
}
