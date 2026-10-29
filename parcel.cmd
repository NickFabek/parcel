@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "ROOT=%~dp0"
set "CATALOG=%ROOT%_packages.tsv"
set "STATE=%ROOT%_state.tsv"
set "REPOS=%ROOT%repos.tsv"
set "PACKAGES=%ROOT%packages"
set "BIN=%PACKAGES%\bin"

call :initialize || exit /b 1
if "%~1"=="" goto dashboard
if /i "%~1"=="tools" shift
if "%~1"=="" goto dashboard
if /i "%~1"=="catalog" goto catalog
if /i "%~1"=="list" goto list
if /i "%~1"=="install" goto install_command
if /i "%~1"=="remove" goto remove_command
if /i "%~1"=="update" goto update_command
if /i "%~1"=="repos" goto repos_command
goto usage

:dashboard
call :tui
exit /b %errorlevel%

:: Combined TUI -------------------------------------------------------------
:tui
setlocal EnableExtensions EnableDelayedExpansion
for /f "delims=#" %%E in ('"prompt #$E# & for %%E in (1) do rem"') do set "ESC=%%E"
set "TUI_TAB=tools"
set /a TUI_TOOLS_CURSOR=1, TUI_REPOS_CURSOR=1
set "TUI_TOOLS_SELECTED="
set "TUI_REPOS_SELECTED="
set "TUI_STATUS="
set "TUI_OUTPUT=%TEMP%\parcel-tui-%RANDOM%-%RANDOM%.txt"
set "TUI_CARET=^^"
set "TUI_LT=<"
set "TUI_GT=>"
<nul set /p "=!ESC![?1049h!ESC![?25l!ESC![H"
call :tui_load

:tui_loop
call :tui_render
call :tui_get_key
if not defined TUI_KEY goto tui_quit
set "TUI_STATUS="
if defined TUI_EXTENDED (
    if /i "!TUI_KEY!"=="H" call :tui_move -1
    if /i "!TUI_KEY!"=="P" call :tui_move 1
    if /i "!TUI_KEY!"=="K" call :tui_switch
    if /i "!TUI_KEY!"=="M" call :tui_switch
    goto tui_loop
)
if "!TUI_KEY!"=="k" call :tui_move -1
if "!TUI_KEY!"=="j" call :tui_move 1
if "!TUI_KEY!"=="K" call :tui_move -10
if "!TUI_KEY!"=="J" call :tui_move 10
if "!TUI_KEY!"=="h" call :tui_switch
if "!TUI_KEY!"=="l" call :tui_switch
if "!TUI_KEY!"==" " call :tui_toggle_current
if "!TUI_KEY!"=="*" call :tui_select_all
if "!TUI_KEY!"=="+" if "!TUI_TAB!"=="tools" (call :tui_action package_install) else call :tui_action repo_commit
if "!TUI_KEY!"=="!TUI_CARET!" if "!TUI_TAB!"=="tools" call :tui_action package_update
if "!TUI_KEY!"=="-" if "!TUI_TAB!"=="tools" (call :tui_action package_remove) else call :tui_action repo_rollback
if "!TUI_KEY!"=="!TUI_LT!" if "!TUI_TAB!"=="repos" call :tui_action repo_pull
if "!TUI_KEY!"=="!TUI_GT!" if "!TUI_TAB!"=="repos" call :tui_action repo_push
if "!TUI_KEY!"=="q" goto tui_quit
goto tui_loop

:tui_quit
del /q "!TUI_OUTPUT!" 2>nul
<nul set /p "=!ESC![?25h!ESC![?1049l"
endlocal
exit /b 0

:tui_get_key
set "TUI_KEY="
set "TUI_EXTENDED="
call :tui_read_key TUI_KEY
if not defined TUI_KEY exit /b 0
if "!TUI_KEY!"=="!" set "TUI_KEY= "
if not "!TUI_KEY:~1,1!"=="" (
    set "TUI_EXTENDED=1"
    set "TUI_KEY=!TUI_KEY:~-1!"
)
exit /b 0

:tui_read_key
:: Read one key without Enter using only cmd.exe and Windows' built-in replace.exe.
setlocal DisableDelayedExpansion
(
    endlocal & setlocal DisableDelayedExpansion
    (for /f skip^=1^ delims^=^ eol^= %%A in ('replace.exe ? . /u /w 2^>nul') do for /f delims^=^ eol^= %%B in ("%%A") do (
        endlocal
        if "%%B" equ "" (set "%~1=^!") else set "%~1=%%B"
        setlocal EnableDelayedExpansion
    )) || (
        endlocal
        set "%~1="
        setlocal EnableDelayedExpansion
    )
)
exit /b 0

:tui_load
if "!TUI_TAB!"=="tools" (
    set "TUI_CURSOR=!TUI_TOOLS_CURSOR!"
    set "TUI_SELECTED=!TUI_TOOLS_SELECTED!"
    set /a TUI_TOTAL=0
    for /f "usebackq skip=1 tokens=1 delims=	" %%A in ("!CATALOG!") do set /a TUI_TOTAL+=1
) else (
    set "TUI_CURSOR=!TUI_REPOS_CURSOR!"
    set "TUI_SELECTED=!TUI_REPOS_SELECTED!"
    set /a TUI_TOTAL=0
    for /f "usebackq skip=1 tokens=1 delims=	" %%A in ("!REPOS!") do set /a TUI_TOTAL+=1
)
if !TUI_TOTAL! equ 0 set /a TUI_CURSOR=0
if !TUI_CURSOR! gtr !TUI_TOTAL! set /a TUI_CURSOR=TUI_TOTAL
exit /b 0

:tui_save_tab
if "!TUI_TAB!"=="tools" (
    set "TUI_TOOLS_CURSOR=!TUI_CURSOR!"
    set "TUI_TOOLS_SELECTED=!TUI_SELECTED!"
) else (
    set "TUI_REPOS_CURSOR=!TUI_CURSOR!"
    set "TUI_REPOS_SELECTED=!TUI_SELECTED!"
)
exit /b 0

:tui_switch
call :tui_save_tab
if "!TUI_TAB!"=="tools" (set "TUI_TAB=repos") else set "TUI_TAB=tools"
set "TUI_STATUS="
call :tui_load
exit /b 0

:tui_move
if !TUI_TOTAL! equ 0 exit /b 0
set /a TUI_CURSOR+=%~1
if !TUI_CURSOR! lss 1 set /a TUI_CURSOR=1
if !TUI_CURSOR! gtr !TUI_TOTAL! set /a TUI_CURSOR=TUI_TOTAL
exit /b 0

:tui_current
set "TUI_CURRENT="
set /a TUI_INDEX=0
if "!TUI_TAB!"=="tools" (
    for /f "usebackq skip=1 tokens=1 delims=	" %%A in ("!CATALOG!") do (
        set /a TUI_INDEX+=1
        if !TUI_INDEX! equ !TUI_CURSOR! set "TUI_CURRENT=%%A"
    )
) else (
    for /f "usebackq skip=1 tokens=1 delims=	" %%A in ("!REPOS!") do (
        set /a TUI_INDEX+=1
        if !TUI_INDEX! equ !TUI_CURSOR! set "TUI_CURRENT=%%A"
    )
)
exit /b 0

:tui_toggle_current
if !TUI_TOTAL! equ 0 exit /b 0
call :tui_current
if not defined TUI_CURRENT exit /b 0
set "TUI_FOUND="
set "TUI_NEW_SELECTED="
for %%S in ("!TUI_SELECTED:,=" "!") do if /i "%%~S"=="!TUI_CURRENT!" (
    set "TUI_FOUND=1"
) else if defined TUI_NEW_SELECTED (set "TUI_NEW_SELECTED=!TUI_NEW_SELECTED!,%%~S") else set "TUI_NEW_SELECTED=%%~S"
if not defined TUI_FOUND if defined TUI_NEW_SELECTED (set "TUI_NEW_SELECTED=!TUI_NEW_SELECTED!,!TUI_CURRENT!") else set "TUI_NEW_SELECTED=!TUI_CURRENT!"
set "TUI_SELECTED=!TUI_NEW_SELECTED!"
exit /b 0

:tui_select_all
set "TUI_SELECTED="
if "!TUI_TAB!"=="tools" (
    for /f "usebackq skip=1 tokens=1 delims=	" %%A in ("!CATALOG!") do if defined TUI_SELECTED (set "TUI_SELECTED=!TUI_SELECTED!,%%A") else set "TUI_SELECTED=%%A"
) else (
    for /f "usebackq skip=1 tokens=1 delims=	" %%A in ("!REPOS!") do if defined TUI_SELECTED (set "TUI_SELECTED=!TUI_SELECTED!,%%A") else set "TUI_SELECTED=%%A"
)
exit /b 0

:tui_render
<nul set /p "=!ESC![H"
echo(+----------------------------------------------------------------------------------------------------+
if "!TUI_TAB!"=="tools" (
    echo(^| [ TOOLS ]   REPOS        arrows move/switch ^| space select ^| + install ^| ^^ update ^| - remove ^| q q ^|
) else (
    echo(^|   TOOLS   [ REPOS ]      arrows move/switch ^| space select ^| ^< pull ^| ^> push ^| + commit ^| - rollba ^|
)
echo(+----------------------------------------------------------------------------------------------------+
set /a TUI_INDEX=0
if "!TUI_TAB!"=="tools" (
    for /f "usebackq skip=1 tokens=1 delims=	" %%A in ("!CATALOG!") do (
        set /a TUI_INDEX+=1
        call :tui_render_tool "%%A" !TUI_INDEX!
    )
) else (
    for /f "usebackq skip=1 tokens=1 delims=	" %%A in ("!REPOS!") do (
        set /a TUI_INDEX+=1
        call :tui_render_repo "%%A" !TUI_INDEX!
    )
)
echo(+----------------------------------------------------------------------------------------------------+
set "TUI_LINE=!TUI_STATUS!                                                                                                  "
echo(^| !TUI_LINE:~0,98! ^|
echo(+----------------------------------------------------------------------------------------------------+
<nul set /p "=!ESC![J"
exit /b 0

:tui_render_tool
set "ROW_NAME=%~1"
set "ROW_BINS="
set "ROW_VERSION="
set "ROW_SIZE="
set "ROW_FILES="
for /f "usebackq skip=1 tokens=1,4 delims=	" %%S in ("!CATALOG!") do if /i "%%S"=="!ROW_NAME!" set "ROW_BINS=%%T"
for /f "usebackq skip=1 tokens=1-5 delims=	" %%S in ("!STATE!") do if /i "%%S"=="!ROW_NAME!" (
    set "ROW_VERSION=%%U"
    set "ROW_SIZE=%%V"
    set "ROW_FILES=%%W"
)
if defined ROW_BINS set "ROW_BINS=!ROW_BINS:/=!"
call :tui_size "!ROW_SIZE!" ROW_SIZE_TEXT
set "ROW_MARK= "
for %%Z in ("!TUI_SELECTED:,=" "!") do if /i "%%~Z"=="!ROW_NAME!" set "ROW_MARK=x"
set "ROW_POINTER= "
if %~2 equ !TUI_CURSOR! set "ROW_POINTER=>"
set "ROW_NAME=!ROW_NAME!                  "
set "ROW_VERSION=!ROW_VERSION!              "
set "ROW_SIZE_TEXT=       !ROW_SIZE_TEXT!"
set "ROW_FILES=       !ROW_FILES!"
set "ROW_BINS=!ROW_BINS!                                           "
echo(^| !ROW_POINTER![!ROW_MARK!] !ROW_NAME:~0,18! !ROW_VERSION:~0,14! !ROW_SIZE_TEXT:~-7! !ROW_FILES:~-7! !ROW_BINS:~0,43! ^|
exit /b 0

:tui_render_repo
set "ROW_NAME=%~1"
set "ROW_BRANCHES="
set "ROW_SIZE="
set "ROW_FILES="
set "ROW_LOC="
set "ROW_DATE="
set "ROW_MESSAGE="
for /f "usebackq skip=1 tokens=1,3,5-8,* delims=	" %%S in ("!REPOS!") do if /i "%%S"=="!ROW_NAME!" (
    set "ROW_BRANCHES=%%T"
    set "ROW_SIZE=%%U"
    set "ROW_FILES=%%V"
    set "ROW_LOC=%%W"
    set "ROW_DATE=%%X"
    set "ROW_MESSAGE=%%Y"
)
call :tui_size "!ROW_SIZE!" ROW_SIZE_TEXT
set "ROW_MARK= "
for %%Z in ("!TUI_SELECTED:,=" "!") do if /i "%%~Z"=="!ROW_NAME!" set "ROW_MARK=x"
set "ROW_POINTER= "
if %~2 equ !TUI_CURSOR! set "ROW_POINTER=>"
set "ROW_NAME=!ROW_NAME!                  "
set "ROW_BRANCHES=!ROW_BRANCHES!            "
set "ROW_SIZE_TEXT=       !ROW_SIZE_TEXT!"
set "ROW_FILES=       !ROW_FILES!"
set "ROW_LOC=         !ROW_LOC!"
set "ROW_DATE=!ROW_DATE!          "
set "ROW_MESSAGE=!ROW_MESSAGE!                        "
echo(^| !ROW_POINTER![!ROW_MARK!] !ROW_NAME:~0,18! !ROW_BRANCHES:~0,12! !ROW_SIZE_TEXT:~-7! !ROW_FILES:~-7! !ROW_LOC:~-9! !ROW_DATE:~0,10! !ROW_MESSAGE:~0,24! ^|
exit /b 0

:tui_size
set "SIZE_VALUE=%~1"
set "%~2="
if not defined SIZE_VALUE exit /b 0
set /a SIZE_NUMBER=SIZE_VALUE 2>nul
if !SIZE_NUMBER! geq 1048576 (
    set /a SIZE_WHOLE=SIZE_NUMBER/1048576, SIZE_REMAINDER=SIZE_NUMBER-SIZE_WHOLE*1048576, SIZE_TENTH=SIZE_REMAINDER*10+524288
    set /a SIZE_TENTH/=1048576
    set "%~2=!SIZE_WHOLE!.!SIZE_TENTH!G"
) else if !SIZE_NUMBER! geq 1024 (
    set /a SIZE_WHOLE=SIZE_NUMBER/1024, SIZE_REMAINDER=SIZE_NUMBER-SIZE_WHOLE*1024, SIZE_TENTH=SIZE_REMAINDER*10+512
    set /a SIZE_TENTH/=1024
    set "%~2=!SIZE_WHOLE!.!SIZE_TENTH!M"
) else set "%~2=!SIZE_NUMBER!K"
exit /b 0

:tui_action
if not defined TUI_SELECTED (
    set "TUI_STATUS=Select at least one item first."
    exit /b 0
)
set "TUI_ACTION=%~1"
set "TUI_MESSAGE="
if "!TUI_ACTION!"=="repo_push" call :tui_prompt_message
if "!TUI_ACTION!"=="repo_commit" call :tui_prompt_message
if "!TUI_ACTION!"=="repo_push" if not defined TUI_MESSAGE exit /b 0
if "!TUI_ACTION!"=="repo_commit" if not defined TUI_MESSAGE exit /b 0
if "!TUI_ACTION!"=="repo_rollback" (
    <nul set /p "=!ESC![?25h"
    echo(
    set "TUI_ANSWER="
    set /p "TUI_ANSWER=Type ROLLBACK to discard each selected repository latest commit and local changes: "
    <nul set /p "=!ESC![?25l"
    if not "!TUI_ANSWER!"=="ROLLBACK" (
        set "TUI_STATUS=Rollback cancelled."
        exit /b 0
    )
)
>"!TUI_OUTPUT!" type nul
set "TUI_COMPLETED="
for %%N in ("!TUI_SELECTED:,=" "!") do if not "%%~N"=="" call :tui_run_one "%%~N"
if not defined TUI_STATUS set "TUI_STATUS=Done: !TUI_COMPLETED!"
set "TUI_SELECTED="
call :tui_save_tab
call :tui_load
exit /b 0

:tui_prompt_message
<nul set /p "=!ESC![?25h"
echo(
set /p "TUI_MESSAGE=Commit message: "
<nul set /p "=!ESC![?25l"
if not defined TUI_MESSAGE set "TUI_STATUS=Cancelled: no message."
exit /b 0

:tui_run_one
set "TUI_NAME=%~1"
set "TUI_RESULT=0"
if "%TUI_ACTION:~0,8%"=="package_" (
    set "TUI_STATUS=Installing !TUI_NAME! [##############################]"
    call :tui_render
)
setlocal DisableDelayedExpansion
if "%TUI_ACTION:~0,8%"=="package_" (
    call :load_catalog "%TUI_NAME%" >nul 2>&1
    if errorlevel 1 (
        endlocal
        exit /b 0
    )
)
if "%TUI_ACTION%"=="package_install" call :install_or_update "%TUI_NAME%" >>"%TUI_OUTPUT%" 2>&1
if "%TUI_ACTION%"=="package_update" call :update_package "%TUI_NAME%" >>"%TUI_OUTPUT%" 2>&1
if "%TUI_ACTION%"=="package_remove" call :remove_package "%TUI_NAME%" >>"%TUI_OUTPUT%" 2>&1
if "%TUI_ACTION%"=="repo_pull" call :repo_action pull "%TUI_NAME%" >>"%TUI_OUTPUT%" 2>&1
if "%TUI_ACTION%"=="repo_push" call :repo_action push "%TUI_NAME%" "%TUI_MESSAGE%" >>"%TUI_OUTPUT%" 2>&1
if "%TUI_ACTION%"=="repo_commit" call :repo_action commit "%TUI_NAME%" "%TUI_MESSAGE%" >>"%TUI_OUTPUT%" 2>&1
if "%TUI_ACTION%"=="repo_rollback" call :repo_action rollback "%TUI_NAME%" >>"%TUI_OUTPUT%" 2>&1
set "TUI_RESULT=%errorlevel%"
endlocal & set "TUI_RESULT=%TUI_RESULT%"
if "!TUI_RESULT!"=="0" (
    if defined TUI_COMPLETED (set "TUI_COMPLETED=!TUI_COMPLETED!, !TUI_NAME!") else set "TUI_COMPLETED=!TUI_NAME!"
) else (
    set "TUI_LAST="
    for /f "usebackq delims=" %%L in ("!TUI_OUTPUT!") do set "TUI_LAST=%%L"
    set "TUI_STATUS=Failed: !TUI_NAME! - !TUI_LAST!"
)
exit /b 0

:catalog
type "%CATALOG%"
exit /b 0

:list
call :print_state
exit /b %errorlevel%

:install_command
shift
if "%~1"=="" goto usage
:install_loop
if "%~1"=="" exit /b 0
call :install_package "%~1" || exit /b 1
shift
goto install_loop

:remove_command
shift
if "%~1"=="" goto usage
if /i "%~1"=="all" (
    for /f "usebackq skip=1 tokens=1 delims=	" %%P in ("%STATE%") do call :remove_package "%%P" || exit /b 1
    exit /b 0
)
:remove_loop
if "%~1"=="" exit /b 0
call :remove_package "%~1" || exit /b 1
shift
goto remove_loop

:update_command
shift
if "%~1"=="" goto update_all
if /i "%~1"=="all" goto update_all
:update_loop
if "%~1"=="" exit /b 0
call :update_package "%~1" || exit /b 1
shift
goto update_loop
:update_all
for /f "usebackq skip=1 tokens=1 delims=	" %%P in ("%STATE%") do call :update_package "%%P" || exit /b 1
exit /b 0

:repos_command
shift
if "%~1"=="" goto usage
if /i "%~1"=="list" goto repos_list
if /i "%~1"=="refresh" goto repos_refresh
if /i "%~1"=="pull" goto repos_pull
if /i "%~1"=="rollback" goto repos_rollback
if /i "%~1"=="push" goto repos_write
if /i "%~1"=="commit" goto repos_write
goto usage

:repos_list
echo REPOSITORY        BRANCHES        DATE        LAST COMMIT
for /f "usebackq skip=1 tokens=1,3,8,* delims=	" %%A in ("%REPOS%") do echo %%A              %%B              %%C  %%D
exit /b 0

:repos_refresh
shift
if "%~1"=="" (
    for /f "usebackq skip=1 tokens=1 delims=	" %%R in ("%REPOS%") do call :sync_repo "%%R" || exit /b 1
    exit /b 0
)
:repos_refresh_loop
if "%~1"=="" exit /b 0
call :sync_repo "%~1" || exit /b 1
shift
goto repos_refresh_loop

:repos_pull
shift
if "%~1"=="" goto usage
:repos_pull_loop
if "%~1"=="" exit /b 0
call :repo_action pull "%~1" || exit /b 1
shift
goto repos_pull_loop

:repos_rollback
shift
if "%~1"=="" goto usage
:repos_rollback_loop
if "%~1"=="" exit /b 0
call :repo_action rollback "%~1" || exit /b 1
shift
goto repos_rollback_loop

:repos_write
set "REPO_ACTION=%~1"
shift
set "REPO_NAMES="
set "REPO_MESSAGE="
:repos_write_parse
if "%~1"=="" goto repos_write_run
if "%~1"=="--message" (
    shift
    if "%~1"=="" goto usage
    set "REPO_MESSAGE=%~1"
    shift
    goto repos_write_parse
)
set "REPO_NAMES=%REPO_NAMES% %~1"
shift
goto repos_write_parse
:repos_write_run
if not defined REPO_NAMES goto usage
if not defined REPO_MESSAGE goto usage
for %%R in (%REPO_NAMES%) do call :repo_action "%REPO_ACTION%" "%%~R" "%REPO_MESSAGE%" || exit /b 1
exit /b 0

:usage
echo Error: Usage: parcel [catalog^|list^|install PKG...^|remove PKG...^|update [PKG...^|all]^|repos list^|refresh [REPO...]^|pull REPO...^|push REPO... --message MSG^|commit REPO... --message MSG^|rollback REPO...] 1>&2
exit /b 1

:initialize
if not exist "%BIN%\" mkdir "%BIN%" || exit /b 1
if not exist "%STATE%" >"%STATE%" echo PACKAGE	DATE	VERSION	SIZE_KB	FILES
if not exist "%REPOS%" >"%REPOS%" echo REPOSITORY	REMOTE_URL	BRANCHES	LOCAL_URL	SIZE_KB	FILES	LOC	DATE	LAST_COMMIT
set "PATH=%PATH%;%BIN%"
for /f "tokens=2,*" %%A in ('reg.exe query HKCU\Environment /v Path 2^>nul ^| findstr.exe /i "Path"') do set "USER_PATH=%%B"
call :persist_user_path
exit /b 0

:persist_user_path
if not defined USER_PATH goto persist_initial_path
set "PATH_CHECK=%TEMP%\parcel-path-%RANDOM%.txt"
>"%PATH_CHECK%" <nul set /p "=%USER_PATH%"
findstr.exe /i /l /c:"%BIN%" "%PATH_CHECK%" >nul
set "PATH_FOUND=%errorlevel%"
del /q "%PATH_CHECK%" 2>nul
if "%PATH_FOUND%"=="0" exit /b 0
reg.exe add HKCU\Environment /v Path /t REG_EXPAND_SZ /d "%USER_PATH%;%BIN%" /f >nul 2>&1
exit /b 0
:persist_initial_path
reg.exe add HKCU\Environment /v Path /t REG_EXPAND_SZ /d "%BIN%" /f >nul 2>&1
exit /b 0

:print_state
echo PACKAGE            VERSION         DATE        SIZE_KB    FILES
for /f "usebackq skip=1 tokens=1-5 delims=	" %%A in ("%STATE%") do echo %%A                %%C              %%B  %%D        %%E
exit /b 0

:print_tools_dashboard
echo ^| PACKAGE             VERSION          SIZE_KB     FILES     COMMANDS                               ^|
for /f "usebackq skip=1 tokens=1,4 delims=	" %%A in ("%CATALOG%") do call :print_tool_row "%%A" "%%B"
exit /b 0

:print_tool_row
set "ROW_VERSION=-"
set "ROW_SIZE=-"
set "ROW_FILES=-"
for /f "usebackq skip=1 tokens=1-5 delims=	" %%A in ("%STATE%") do if /i "%%A"=="%~1" (
    set "ROW_VERSION=%%C"
    set "ROW_SIZE=%%D"
    set "ROW_FILES=%%E"
)
echo ^| %~1                 %ROW_VERSION%               %ROW_SIZE%          %ROW_FILES%         %~2
exit /b 0

:print_repos_dashboard
echo ^| REPOSITORY          BRANCHES          DATE          LAST COMMIT                                      ^|
for /f "usebackq skip=1 tokens=1,3,8,* delims=	" %%A in ("%REPOS%") do echo ^| %%A                 %%B                %%C    %%D
exit /b 0

:load_catalog
set "PACKAGE_NAME="
set "PACKAGE_URL="
set "PACKAGE_PATTERN="
set "PACKAGE_BINARIES="
for /f "usebackq skip=1 tokens=1-4 delims=	" %%A in ("%CATALOG%") do if /i "%%A"=="%~1" (
    set "PACKAGE_NAME=%%A"
    set "PACKAGE_URL=%%B"
    set "PACKAGE_PATTERN=%%C"
    set "PACKAGE_BINARIES=%%D"
)
if not defined PACKAGE_NAME (
    echo Error: Unknown package: %~1 1>&2
    exit /b 1
)
exit /b 0

:get_release
call :load_catalog "%~1" || exit /b 1
set "GITHUB_REPO=%PACKAGE_URL:https://github.com/=%"
set "RELEASE_DIR=%TEMP%\parcel-release-%RANDOM%-%RANDOM%"
mkdir "%RELEASE_DIR%" || exit /b 1
set "RELEASE_PAGE="
for /f "delims=" %%V in ('curl.exe -fsSL -o NUL -w "%%{url_effective}" "https://github.com/%GITHUB_REPO%/releases/latest"') do set "RELEASE_PAGE=%%V"
if not defined RELEASE_PAGE (
    rmdir /s /q "%RELEASE_DIR%"
    echo Error: Could not read GitHub release for %~1 1>&2
    exit /b 1
)
for %%V in ("%RELEASE_PAGE%") do set "RELEASE_VERSION=%%~nxV"
curl.exe -fsSL -H "User-Agent: parcel" "https://github.com/%GITHUB_REPO%/releases/expanded_assets/%RELEASE_VERSION%" -o "%RELEASE_DIR%\assets.html"
if errorlevel 1 (
    rmdir /s /q "%RELEASE_DIR%"
    echo Error: Could not read GitHub release assets for %~1 1>&2
    exit /b 1
)
>"%RELEASE_DIR%\urls.txt" (for /f "tokens=2 delims==" %%U in ('findstr.exe /c:"/releases/download/" "%RELEASE_DIR%\assets.html"') do for /f "tokens=1" %%H in ("%%U") do echo https://github.com%%~H)
set "RELEASE_URL="
if /i "%PACKAGE_NAME%"=="workerd" for /f "usebackq delims=" %%U in (`findstr.exe /i /l /c:"workerd-windows-64.gz" "%RELEASE_DIR%\urls.txt"`) do if not defined RELEASE_URL set "RELEASE_URL=%%U"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
    if not defined RELEASE_URL for /f "usebackq delims=" %%U in (`findstr.exe /i "windows" "%RELEASE_DIR%\urls.txt" ^| findstr.exe /i "arm64 aarch64" ^| findstr.exe /i ".zip .gz .xz .tgz" ^| findstr.exe /i /v ".sha256 .sum .from-"`) do if not defined RELEASE_URL set "RELEASE_URL=%%U"
) else (
    if not defined RELEASE_URL for /f "usebackq delims=" %%U in (`findstr.exe /i "windows" "%RELEASE_DIR%\urls.txt" ^| findstr.exe /i "x86_64 amd64 64" ^| findstr.exe /i ".zip .gz .xz .tgz" ^| findstr.exe /i /v ".sha256 .sum .from-"`) do if not defined RELEASE_URL set "RELEASE_URL=%%U"
)
if not defined RELEASE_URL (
    if /i "%PACKAGE_NAME%"=="workerd" (
        set "RELEASE_VERSION=v1.20260801.1"
        echo Latest workerd release has no Windows binary; using v1.20260801.1.
        curl.exe -fsSL -H "User-Agent: parcel" "https://github.com/%GITHUB_REPO%/releases/expanded_assets/v1.20260801.1" -o "%RELEASE_DIR%\assets.html"
        if errorlevel 1 (
            rmdir /s /q "%RELEASE_DIR%"
            echo Error: Could not read fallback release assets for workerd. 1>&2
            exit /b 1
        )
        >"%RELEASE_DIR%\urls.txt" (for /f "tokens=2 delims==" %%U in ('findstr.exe /c:"/releases/download/" "%RELEASE_DIR%\assets.html"') do for /f "tokens=1" %%H in ("%%U") do echo https://github.com%%~H)
        for /f "usebackq delims=" %%U in (`findstr.exe /i /l /c:"workerd-windows-64.gz" "%RELEASE_DIR%\urls.txt"`) do if not defined RELEASE_URL set "RELEASE_URL=%%U"
    )
    if not defined RELEASE_URL (
        rmdir /s /q "%RELEASE_DIR%"
        echo Error: No matching Windows release asset for %~1 1>&2
        exit /b 1
    )
)
set "RELEASE_URL=%RELEASE_URL: =%"
set "RELEASE_URL=%RELEASE_URL:"=%"
set "RELEASE_URL=%RELEASE_URL:,=%"
for %%F in ("%RELEASE_URL%") do set "RELEASE_FILE=%%~nxF"
exit /b 0

:install_package
call :get_release "%~1" || exit /b 1
set "STAGE=%TEMP%\parcel-%RANDOM%-%RANDOM%"
set "UNPACKED=%STAGE%\unpacked"
set "ARCHIVE=%STAGE%\%RELEASE_FILE%"
set "DESTINATION=%PACKAGES%\%PACKAGE_NAME%"
mkdir "%UNPACKED%" || exit /b 1
echo Installing %PACKAGE_NAME% %RELEASE_VERSION%...
curl.exe -fL "%RELEASE_URL%" -o "%ARCHIVE%"
if errorlevel 1 goto install_failed
if /i "%RELEASE_FILE:~-3%"==".gz" (
    if /i not "%RELEASE_FILE:~-7%"==".tar.gz" (
        set "PARCEL_GZIP_SOURCE=%ARCHIVE%"
        set "PARCEL_GZIP_DESTINATION=%UNPACKED%\%RELEASE_FILE:~0,-3%"
        powershell.exe -NoProfile -NonInteractive -Command "$ErrorActionPreference = 'Stop'; try { $source = [System.IO.File]::OpenRead($env:PARCEL_GZIP_SOURCE); try { $gzip = [System.IO.Compression.GzipStream]::new($source, [System.IO.Compression.CompressionMode]::Decompress); try { $destination = [System.IO.File]::Create($env:PARCEL_GZIP_DESTINATION); try { $gzip.CopyTo($destination) } finally { $destination.Dispose() } } finally { $gzip.Dispose() } } finally { $source.Dispose() } } catch { Write-Error $_; exit 1 }"
        set "PARCEL_GZIP_SOURCE="
        set "PARCEL_GZIP_DESTINATION="
    ) else (
        tar.exe -xf "%ARCHIVE%" -C "%UNPACKED%"
    )
) else (
    tar.exe -xf "%ARCHIVE%" -C "%UNPACKED%"
)
if errorlevel 1 goto install_failed
if exist "%DESTINATION%\" rmdir /s /q "%DESTINATION%"
mkdir "%DESTINATION%" || goto install_failed
robocopy.exe "%UNPACKED%" "%DESTINATION%" /E /MOVE /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 goto install_failed
call :write_launchers || goto install_failed
set /a FILE_COUNT=0
set /a TOTAL_BYTES=0
for /r "%DESTINATION%" %%F in (*) do (
    set /a FILE_COUNT+=1
    set /a TOTAL_BYTES+=%%~zF
)
set /a SIZE_KB=TOTAL_BYTES/1024
call :save_state "%PACKAGE_NAME%" "%RELEASE_VERSION%" "%SIZE_KB%" "%FILE_COUNT%" || goto install_failed
rmdir /s /q "%STAGE%" 2>nul
rmdir /s /q "%RELEASE_DIR%" 2>nul
echo Installed %PACKAGE_NAME% %RELEASE_VERSION%.
exit /b 0
:install_failed
rmdir /s /q "%STAGE%" 2>nul
rmdir /s /q "%RELEASE_DIR%" 2>nul
echo Error: Installation failed for %~1 1>&2
exit /b 1

:write_launchers
setlocal EnableDelayedExpansion
set "BINS=%PACKAGE_BINARIES%"
set "BINS=!BINS:/=!"
set "BINS=!BINS:,= !"
for %%B in (!BINS!) do (
    set "FOUND="
    for /r "%DESTINATION%" %%F in (*) do if /i "%%~nxF"=="%%B" if not defined FOUND set "FOUND=%%F"
    if not defined FOUND for /r "%DESTINATION%" %%F in (*) do if /i "%%~nxF"=="%%B.exe" if not defined FOUND set "FOUND=%%F"
    if not defined FOUND for /r "%DESTINATION%" %%F in (%%B-*) do if not defined FOUND set "FOUND=%%F"
    if defined FOUND (
        if /i "%PACKAGE_NAME%"=="workerd" if /i not "!FOUND:~-4!"==".exe" (
            move /y "!FOUND!" "%DESTINATION%\workerd.exe" >nul || (
                echo Error: Could not prepare the workerd executable. 1>&2
                endlocal
                exit /b 1
            )
            set "FOUND=%DESTINATION%\workerd.exe"
        )
        set "LAUNCHER=%BIN%\%%B.cmd"
        del /f /q "%BIN%\%%B" "%BIN%\%%B.exe" "!LAUNCHER!" 2>nul
        >"!LAUNCHER!" (
            echo @echo off
            echo "!FOUND!" %%*
        )
        if errorlevel 1 (
            echo Error: Could not create launcher for %%B. 1>&2
            endlocal
            exit /b 1
        )
    ) else (
        echo Warning: %%B was not found in %PACKAGE_NAME%. 1>&2
    )
)
endlocal
exit /b 0

:save_state
set "STATE_TEMP=%STATE%.tmp"
>"%STATE_TEMP%" (
    for /f "usebackq delims=" %%L in ("%STATE%") do for /f "tokens=1 delims=	" %%A in ("%%L") do if /i not "%%A"=="%~1" echo %%L
    echo %~1	%DATE%	%~2	%~3	%~4
)
move /y "%STATE_TEMP%" "%STATE%" >nul
exit /b %errorlevel%

:remove_package
call :load_catalog "%~1" || exit /b 1
if not exist "%PACKAGES%\%PACKAGE_NAME%\" (
    echo Error: %PACKAGE_NAME% is not installed 1>&2
    exit /b 1
)
setlocal EnableDelayedExpansion
set "BINS=%PACKAGE_BINARIES%"
set "BINS=!BINS:/=!"
set "BINS=!BINS:,= !"
for %%B in (!BINS!) do (
    del /f /q "%BIN%\%%B" 2>nul
    del /f /q "%BIN%\%%B.exe" 2>nul
    del /f /q "%BIN%\%%B.cmd" 2>nul
)
endlocal
rmdir /s /q "%PACKAGES%\%PACKAGE_NAME%"
set "STATE_TEMP=%STATE%.tmp"
>"%STATE_TEMP%" (for /f "usebackq delims=" %%L in ("%STATE%") do for /f "tokens=1 delims=	" %%A in ("%%L") do if /i not "%%A"=="%PACKAGE_NAME%" echo %%L)
move /y "%STATE_TEMP%" "%STATE%" >nul
echo Removed %PACKAGE_NAME%.
exit /b 0

:update_package
set "INSTALLED_VERSION="
for /f "usebackq skip=1 tokens=1,3 delims=	" %%A in ("%STATE%") do if /i "%%A"=="%~1" set "INSTALLED_VERSION=%%B"
if not defined INSTALLED_VERSION (
    echo Error: %~1 is not installed 1>&2
    exit /b 1
)
call :get_release "%~1" || exit /b 1
if "%INSTALLED_VERSION%"=="%RELEASE_VERSION%" (
    set "DESTINATION=%PACKAGES%\%PACKAGE_NAME%"
    call :write_launchers || (
        rmdir /s /q "%RELEASE_DIR%" 2>nul
        exit /b 1
    )
    echo %~1 is already %RELEASE_VERSION%.
    rmdir /s /q "%RELEASE_DIR%" 2>nul
    exit /b 0
)
rmdir /s /q "%RELEASE_DIR%" 2>nul
call :install_package "%~1"
exit /b %errorlevel%

:install_or_update
set "INSTALLED_VERSION="
for /f "usebackq skip=1 tokens=1,3 delims=	" %%A in ("%STATE%") do if /i "%%A"=="%~1" set "INSTALLED_VERSION=%%B"
if defined INSTALLED_VERSION (
    call :update_package "%~1"
) else (
    call :install_package "%~1"
)
exit /b %errorlevel%

:load_repo
set "REPO_NAME="
set "REPO_LOCAL="
for /f "usebackq skip=1 tokens=1,4 delims=	" %%A in ("%REPOS%") do if /i "%%A"=="%~1" (
    set "REPO_NAME=%%A"
    set "REPO_LOCAL=%%B"
)
if not defined REPO_NAME (
    echo Error: Unknown repository: %~1 1>&2
    exit /b 1
)
if "%REPO_LOCAL:~0,2%"=="~/" set "REPO_LOCAL=%USERPROFILE%\%REPO_LOCAL:~2%"
if "%REPO_LOCAL:~0,2%"=="~\" set "REPO_LOCAL=%USERPROFILE%\%REPO_LOCAL:~2%"
if not exist "%REPO_LOCAL%\.git\" (
    echo Error: %REPO_NAME% is not a Git repository at %REPO_LOCAL% 1>&2
    exit /b 1
)
exit /b 0

:repo_action
call :load_repo "%~2" || exit /b 1
if /i "%~1"=="pull" (
    for /f "delims=" %%B in ('git.exe -C "%REPO_LOCAL%" branch --show-current') do set "BRANCH=%%B"
    if not defined BRANCH (
        echo Error: %REPO_NAME% is in detached HEAD state 1>&2
        exit /b 1
    )
    call git.exe -C "%REPO_LOCAL%" pull --ff-only origin "%%BRANCH%%" || exit /b 1
)
if /i "%~1"=="commit" git.exe -C "%REPO_LOCAL%" commit -m "%~3" || exit /b 1
if /i "%~1"=="push" (
    for /f "delims=" %%B in ('git.exe -C "%REPO_LOCAL%" branch --show-current') do set "BRANCH=%%B"
    if not defined BRANCH (
        echo Error: %REPO_NAME% is in detached HEAD state 1>&2
        exit /b 1
    )
    git.exe -C "%REPO_LOCAL%" add -A || exit /b 1
    git.exe -C "%REPO_LOCAL%" commit -m "%~3" || exit /b 1
    call git.exe -C "%REPO_LOCAL%" push origin "%%BRANCH%%" || exit /b 1
)
if /i "%~1"=="rollback" (
    git.exe -C "%REPO_LOCAL%" rev-parse --verify HEAD~1 >nul || exit /b 1
    git.exe -C "%REPO_LOCAL%" reset --hard HEAD~1 || exit /b 1
    git.exe -C "%REPO_LOCAL%" clean -fd || exit /b 1
)
call :sync_repo "%REPO_NAME%"
exit /b %errorlevel%

:sync_repo
call :load_repo "%~1" || exit /b 1
set "REMOTE_URL="
set "BRANCHES="
set "LAST_DATE="
set "LAST_COMMIT="
for /f "delims=" %%A in ('git.exe -C "%REPO_LOCAL%" remote get-url origin 2^>nul') do set "REMOTE_URL=%%A"
for /f "delims=" %%A in ('git.exe -C "%REPO_LOCAL%" for-each-ref --format="%%(refname:short)" refs/heads') do call set "BRANCHES=%%BRANCHES%%,%%A"
if defined BRANCHES set "BRANCHES=%BRANCHES:~1%"
for /f "delims=" %%A in ('git.exe -C "%REPO_LOCAL%" log -1 --format=%%cs') do set "LAST_DATE=%%A"
for /f "delims=" %%A in ('git.exe -C "%REPO_LOCAL%" log -1 --format=%%s') do set "LAST_COMMIT=%%A"
set /a REPO_FILES=0
set /a REPO_BYTES=0
set /a REPO_LOC=0
for /f "delims=" %%F in ('dir /a-d /s /b "%REPO_LOCAL%" 2^>nul ^| findstr.exe /i /v /c:"\.git\"') do (
    set /a REPO_FILES+=1
    set /a REPO_BYTES+=%%~zF
    for /f "delims=" %%L in ('find.exe /v /c "" ^< "%%F" 2^>nul') do set /a REPO_LOC+=%%L
)
set /a REPO_SIZE=REPO_BYTES/1024
set "REPOS_TEMP=%REPOS%.tmp"
>"%REPOS_TEMP%" (
    for /f "usebackq delims=" %%L in ("%REPOS%") do for /f "tokens=1 delims=	" %%A in ("%%L") do if /i "%%A"=="%REPO_NAME%" (
        echo %REPO_NAME%	%REMOTE_URL%	%BRANCHES%	%REPO_LOCAL%	%REPO_SIZE%	%REPO_FILES%	%REPO_LOC%	%LAST_DATE%	%LAST_COMMIT%
    ) else echo %%L
)
move /y "%REPOS_TEMP%" "%REPOS%" >nul
exit /b %errorlevel%
