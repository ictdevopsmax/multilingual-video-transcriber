cmake_minimum_required(VERSION 3.15)
project(TranskripsiVideoOffline CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Source file
add_executable(TranskripsiGUI WIN32 transkripsi_gui.cpp)

# Include directory untuk vosk_api.h
target_include_directories(TranskripsiGUI PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

# Link libraries (Win32 Common Controls, Dialogs, Shell, dan Vosk)
find_library(VOSK_LIB libvosk PATHS ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/.. NO_DEFAULT_PATH)
if(VOSK_LIB)
    target_link_libraries(TranskripsiGUI PRIVATE ${VOSK_LIB} comctl32 comdlg32 shell32)
else()
    target_link_libraries(TranskripsiGUI PRIVATE libvosk comctl32 comdlg32 shell32)
endif()

