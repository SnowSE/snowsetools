# :snapshot dumps page HTML to tmp/screens for the screenshot script; it writes
# files and is not an assertion, so it only runs when asked for by name.
ExUnit.start(exclude: [:snapshot])
SnowSeTools.TestDatabase.reset!()
SnowSeTools.TestDatabase.seed_access_control!()
