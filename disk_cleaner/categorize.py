CATEGORY_BY_EXT = {
    # text
    ".txt": "text", ".md": "text", ".log": "text", ".csv": "text", ".tsv": "text",
    ".json": "text", ".xml": "text", ".yaml": "text", ".yml": "text", ".ini": "text",
    ".cfg": "text", ".conf": "text", ".toml": "text", ".rst": "text",

    # office
    ".doc": "office", ".docx": "office", ".dot": "office", ".dotx": "office",
    ".xls": "office", ".xlsx": "office", ".xlsm": "office", ".xlt": "office",
    ".ppt": "office", ".pptx": "office", ".pps": "office", ".ppsx": "office",
    ".odt": "office", ".ods": "office", ".odp": "office",
    ".pdf": "office",

    # image
    ".jpg": "image", ".jpeg": "image", ".png": "image", ".gif": "image",
    ".bmp": "image", ".tiff": "image", ".tif": "image", ".webp": "image",
    ".svg": "image", ".ico": "image", ".heic": "image", ".heif": "image",
    ".raw": "image", ".cr2": "image", ".nef": "image", ".arw": "image", ".dng": "image",
    ".psd": "image", ".ai": "image",

    # video
    ".mp4": "video", ".m4v": "video", ".mkv": "video", ".avi": "video",
    ".mov": "video", ".wmv": "video", ".flv": "video", ".webm": "video",
    ".mpg": "video", ".mpeg": "video", ".3gp": "video", ".ts": "video",
    ".mts": "video", ".vob": "video",

    # code
    ".py": "code", ".js": "code", ".mjs": "code", ".cjs": "code",
    ".jsx": "code", ".tsx": "code",
    ".java": "code", ".c": "code", ".cpp": "code", ".cc": "code", ".cxx": "code",
    ".h": "code", ".hpp": "code", ".hh": "code",
    ".go": "code", ".rs": "code", ".rb": "code", ".php": "code",
    ".cs": "code", ".swift": "code", ".kt": "code", ".kts": "code",
    ".scala": "code", ".sh": "code", ".bash": "code", ".zsh": "code",
    ".ps1": "code", ".bat": "code", ".cmd": "code",
    ".sql": "code", ".r": "code", ".pl": "code", ".lua": "code", ".dart": "code",
    ".html": "code", ".htm": "code", ".css": "code", ".scss": "code", ".less": "code",
    ".vue": "code", ".tf": "code",

    # binary
    ".exe": "bin", ".dll": "bin", ".so": "bin", ".dylib": "bin", ".bin": "bin",
    ".iso": "bin", ".img": "bin", ".dmg": "bin",
    ".zip": "bin", ".tar": "bin", ".gz": "bin", ".tgz": "bin", ".bz2": "bin",
    ".xz": "bin", ".7z": "bin", ".rar": "bin", ".zst": "bin",
    ".deb": "bin", ".rpm": "bin", ".msi": "bin", ".apk": "bin",
    ".jar": "bin", ".war": "bin", ".ear": "bin", ".class": "bin",
    ".o": "bin", ".obj": "bin", ".pyc": "bin", ".pyd": "bin", ".whl": "bin",
}


def categorize(extension: str | None) -> str:
    if not extension:
        return "misc"
    return CATEGORY_BY_EXT.get(extension.lower(), "misc")
