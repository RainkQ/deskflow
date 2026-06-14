# SPDX-FileCopyrightText: (C) 2024 Chris Rizzitello <sithlord48@gmail.com>
# SPDX-License-Identifier: MIT

# HACK This is set when the files is included so its the real path
# calling CMAKE_CURRENT_LIST_DIR after include would return the wrong scope var
set(MY_DIR ${CMAKE_CURRENT_LIST_DIR})
set(OSX_BUNDLE ${BUILD_OSX_BUNDLE})

set(OS_STRING "macos-${BUILD_ARCHITECTURE}")

if (OSX_BUNDLE)
  install(CODE "execute_process(COMMAND
    ${DEPLOYQT}
    \"\${CMAKE_INSTALL_PREFIX}/${CMAKE_PROJECT_PROPER_NAME}.app\"
    -timestamp -codesign=-
  )")

  # Fix plugin RPATHs: macdeployqt leaves plugins pointing to Homebrew's Qt,
  # which causes duplicate Qt loading and "no Qt platform plugin" errors.
  # Redirect all plugin RPATHs to the bundled Frameworks directory.
  install(CODE "
    file(GLOB_RECURSE plugins
      \"\${CMAKE_INSTALL_PREFIX}/${CMAKE_PROJECT_PROPER_NAME}.app/Contents/PlugIns/*.dylib\")
    foreach(plugin \${plugins})
      execute_process(COMMAND install_name_tool
        -delete_rpath \"@loader_path/../../../../lib\" \"\${plugin}\"
        ERROR_QUIET)
      execute_process(COMMAND install_name_tool
        -add_rpath \"@loader_path/../../Frameworks\" \"\${plugin}\"
        ERROR_QUIET)
    endforeach()
  ")
  set(CPACK_PACKAGE_ICON "${MY_DIR}/dmg-volume.icns")
  set(CPACK_DMG_BACKGROUND_IMAGE "${MY_DIR}/dmg-background.tiff")
  set(CPACK_DMG_DS_STORE_SETUP_SCRIPT "${MY_DIR}/generate_ds_store.applescript")
  set(CPACK_DMG_VOLUME_NAME "${CMAKE_PROJECT_PROPER_NAME}")
  set(CPACK_DMG_SLA_USE_RESOURCE_FILE_LICENSE ON)
  set(CPACK_GENERATOR "DragNDrop")
endif()
