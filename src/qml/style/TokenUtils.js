function lookup(object, path) {
    var current = object
    var parts = path.split(".")
    for (var i = 0; i < parts.length; i += 1) {
        if (!current || typeof current !== "object" || !(parts[i] in current))
            return undefined
        current = current[parts[i]]
    }
    return current
}

function color(tokens, path, fallback) {
    var token = lookup(tokens, path)
    if (!token || typeof token !== "object")
        return fallback

    var value = token.$value
    if (typeof value === "string")
        return value
    if (value && typeof value.hex === "string")
        return value.hex

    return fallback
}
