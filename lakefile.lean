import Lake
open System Lake DSL

package «ginac-lean» where
  srcDir := "lean"
  precompileModules := true
  -- preferReleaseBuild := get_config? noCloudRelease |>.isNone
  buildType := BuildType.debug
  -- buildArchive? := is_arm? |>.map (if · then "arm64" else "x86_64")
  moreLinkArgs := #[s!"-L{__dir__}/build/lib", 
    -- "-L/usr/bin/../lib/gcc/aarch64-linux-gnu/11 -L/lib/aarch64-linux-gnu -L/usr/lib/aarch64-linux-gnu -L/usr/lib/llvm-14/bin/../lib -L/lib -L/usr/lib",
    "-lginac_ffi", "-lginac", "-lcln", "-lstdc++", "-v"] -- "-v",  --, "-lc++", "-lc++abi", "-lunwind"] -- "-lstdc++"]
  weakLeanArgs := #[
    s!"--load-dynlib={__dir__}/build/lib/" ++ nameToSharedLib "cln",
    s!"--load-dynlib={__dir__}/build/lib/" ++ nameToSharedLib "ginac"
  ]

lean_lib «GinacLean» 

lean_lib «GinacFFI» where
  moreLinkArgs := #[s!"-L{__dir__}/build/lib",
  "-lginac_ffi", 
  "-lstdc++"]
  extraDepTargets := #["libginac_ffi"]

@[default_target]
lean_exe «ginac-lean» where
  root := `Main

def clangxx : String := "clang++"

def getClangSearchPaths : IO (Array FilePath) := do
  let output ← IO.Process.output {
    cmd := "clang++", args := #["-v", "-lstdc++"]
  }
  let mut paths := #[]
  for s in output.stderr.splitOn do
    if s.startsWith "-L/" then
      paths := paths.push (s.drop 2 : FilePath).normalize
  return paths


def getLibPath (name : String) : IO (Option FilePath) := do
  let searchPaths ← getClangSearchPaths
  for path in searchPaths do
    let libPath := path / name
    if ← libPath.pathExists then
      return libPath
  return none


def afterReleaseSync (pkg : Package) (build : SchedulerM (Job α)) : IndexBuildM (Job α) := do
  if pkg.preferReleaseBuild ∧ pkg.name ≠ (← getRootPackage).name then
    (← pkg.release.fetch).bindAsync fun _ _ => build
  else
    build


def afterReleaseAsync (pkg : Package) (build : BuildM α) : IndexBuildM (Job α) := do
  if pkg.preferReleaseBuild ∧ pkg.name ≠ (← getRootPackage).name then
    (← pkg.release.fetch).bindSync fun _ _ => build
  else
    Job.async build

-- #eval ("a.b.c".splitOn ".")[0]

def copyLibJob (pkg : Package) (libName : String) : IndexBuildM (BuildJob FilePath) :=
  afterReleaseAsync pkg do
  if !Platform.isOSX then  -- Only required for Linux
    let dst := pkg.nativeLibDir / libName
    try
      let depTrace := Hash.ofString libName
      let trace ← buildFileUnlessUpToDate dst depTrace do

        -- let srcLeanBundled := (← getLeanSystemLibDir) / libName
        -- proc {
        --   cmd := "ls"
        --   args := #[(srcLeanBundled.toString.splitOn ".")[0]! ++ "*"]
        -- }
        -- let src := srcLeanBundled
        let some src ← getLibPath libName | error s!"{libName} not found"
        logStep s!"Copying from {src} to {dst}"
        proc {
          cmd := "cp"
          args := #[src.toString, dst.toString]
        }
        -- TODO: Use relative symbolic links instead.
        proc {
          cmd := "cp"
          args := #[src.toString, dst.toString.dropRight 2]
        }
        proc {
          cmd := "cp"
          args := #[dst.toString, dst.toString.dropRight 4]
        }
      pure (dst, trace)
    else
      pure (dst, ← computeTrace dst)
  else
    pure ("", .nil)


target libcpp pkg : FilePath := do
  copyLibJob pkg "libc++.so.1.0"


target libcppabi pkg : FilePath := do
  copyLibJob pkg "libc++abi.so.1.0"


target libunwind pkg : FilePath := do
  copyLibJob pkg "libunwind.so.8.0.1"

target libcln pkg : FilePath := do
  afterReleaseAsync pkg do
    let dst := pkg.nativeLibDir / (nameToSharedLib "cln")
    createParentDirs dst
    let depTrace := Hash.ofString dst.toString
    let trace ← buildFileUnlessUpToDate dst depTrace do
      proc {
        cmd := "echo"
        args := #["Looking for", dst.toString]
      }
    return (dst, trace)

target libginac pkg : FilePath := do
  afterReleaseAsync pkg do
    let dst := pkg.nativeLibDir / (nameToSharedLib "ginac")
    createParentDirs dst
    let depTrace := Hash.ofString dst.toString
    let trace ← buildFileUnlessUpToDate dst depTrace do
      proc {
        cmd := "echo"
        args := #["Looking for", dst.toString]
      }
    return (dst, trace)

def buildCpp (pkg : Package) (path : FilePath) (deps : List (BuildJob FilePath)) : SchedulerM (BuildJob FilePath) := do
  let optLevel := if pkg.buildType == .release then "-O3" else "-O0"
  let mut flags := #[
    "-fPIC",
    "-std=c++11",
    -- "-lstdc++",
    -- "-stdlib=libstdc++", -- gcc
    -- "-static-libstdc++", -- gcc
    -- "-stdlib=libc++", -- clang
    -- "-L", (← getLeanSystemLibDir).toString,
    -- "-I", (← getLeanIncludeDir).toString,
    -- "-I", (pkg.buildDir / "include").toString,
    -- "-L", (pkg.buildDir / "lib").toString,
    -- "-lcln",
    -- "-lginac",
    "-v",
    optLevel
  ]
  match get_config? targetArch with
  | none => pure ()
  | some arch => flags := flags.push s!"--target={arch}"
  let args := flags ++ #["-I", (← getLeanIncludeDir).toString, "-I", (pkg.buildDir / "include").toString]
  let oFile := pkg.buildDir / (path.withExtension "o")
  let srcJob ← inputFile <| pkg.dir / path
  buildFileAfterDepList oFile (srcJob :: deps) (extraDepTrace := computeHash flags) fun deps =>
    compileO path.toString oFile deps[0]! args clangxx

target ginac_ffi.o pkg : FilePath := do
  -- let oFile := pkg.buildDir / "cpp" / "ginac_ffi.o"
  -- let srcJob ← inputFile <| pkg.dir / "cpp" / "ginac_ffi.cpp"
  -- let flags := #[
  --   "-fPIC",
  --   "-std=c++11",
  --   "-I", (← getLeanIncludeDir).toString,
  --   "-I", (pkg.buildDir / "installed" / "include").toString,
  --   "-L", (pkg.buildDir / "installed" / "lib").toString,
  --   "-l", "cln",
  --   "-l", "ginac"
  --   ]
  -- TODO figure out why these are required for linking, otherwise
  -- [5/5] Linking ginac-lean
  -- error: > /home/vscode/.elan/toolchains/leanprover--lean4---4.0.0/bin/leanc -o ./build/bin/ginac-lean ./build/ir/Main.o ./build/ir/GinacFFI.o -L./build/lib -lginac_ffi -lginac -lcln -lstdc++
  -- error: stderr:
  -- ld.lld: error: undefined reference due to --no-allow-shlib-undefined: std::ios_base::Init::Init()
  -- >>> referenced by ./build/lib/libginac_ffi.so
  let _cpp ← libcpp.fetch
  let _cppabi ← libcppabi.fetch
  let _unwind ← libunwind.fetch

  let cln ← libcln.fetch
  let ginac ← libginac.fetch
  let build := buildCpp pkg "cpp/ginac_ffi.cpp" [ginac, cln] --, cpp, cppabi, unwind]
  afterReleaseSync pkg build
  -- buildO "ginac_ffi.cpp" oFile srcJob flags "c++"

-- extern_lib libginac_ffi pkg := do
  -- let name := nameToStaticLib "ginac_ffi"
  -- let ffiO ← ginac_ffi.o.fetch
  -- buildStaticLib (pkg.nativeLibDir / name) #[ffiO]

target libginac_ffi pkg : FilePath := do
  let name := nameToSharedLib "ginac_ffi"
  let ffiO ← ginac_ffi.o.fetch
  buildLeanSharedLib (pkg.nativeLibDir / name) #[ffiO] #["-lstdc++", "-v"]

