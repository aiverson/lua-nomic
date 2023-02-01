  return {
    name = "aiverson/codeclicker",
    version = "0.0.1",
    description = "A prototype of the game mechanics for Project Kardashev",
    tags = { },
    license = "MIT",
    author = { name = "aiverson", email = "alexjiverson@gmail.com" },
    homepage = "",
    public = false,
    dependencies = {
      "creationix/weblit@3.1.0",
      "luvit/luvit@2.0.0",
      "creationix/coro-fs@2.2.1",
      "creationix/coro-split@2.0.0",
      "LeXinshou/discordoauth2"
    },
    files = {
      "**.lua",
      "**.js",
      "**.html",
      "**.css",
      "!test*"
    }
  }
