from disk_cleaner.categorize import categorize


def test_known_extensions():
    assert categorize(".docx") == "office"
    assert categorize(".pdf") == "office"
    assert categorize(".png") == "image"
    assert categorize(".mp4") == "video"
    assert categorize(".py") == "code"
    assert categorize(".exe") == "bin"
    assert categorize(".txt") == "text"


def test_unknown_extension_is_misc():
    assert categorize(".xyzunknown") == "misc"


def test_none_or_empty_is_misc():
    assert categorize(None) == "misc"
    assert categorize("") == "misc"


def test_case_insensitive():
    assert categorize(".DOCX") == "office"
    assert categorize(".JPG") == "image"
    assert categorize(".Mp4") == "video"
