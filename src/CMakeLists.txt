cmake_minimum_required(VERSION 3.16)
project(flutter_aubio VERSION 1.0.0 LANGUAGES C)

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Options for controlling aubio build features
option(AUBIO_BUILD_SHARED "Build shared library" ON)
option(AUBIO_BUILD_TESTS "Build tests" OFF)
option(AUBIO_BUILD_EXAMPLES "Build examples" OFF)
option(AUBIO_BUILD_DOC "Build documentation" OFF)
option(AUBIO_BUILD_TOOLS "Build command-line tools" OFF)

# Audio analysis features
option(AUBIO_ENABLE_ONSET "Enable onset detection" ON)
option(AUBIO_ENABLE_PITCH "Enable pitch detection" ON)
option(AUBIO_ENABLE_TEMPO "Enable tempo tracking" ON)
option(AUBIO_ENABLE_NOTES "Enable note detection" ON)
option(AUBIO_ENABLE_MFCC "Enable MFCC computation" ON)
option(AUBIO_ENABLE_FFT "Enable FFT" ON)

# External dependencies control (disable to reduce complexity)
option(AUBIO_DISABLE_AVCODEC "Disable libavcodec support" ON)
option(AUBIO_DISABLE_SNDFILE "Disable libsndfile support" ON)
option(AUBIO_DISABLE_SAMPLERATE "Disable libsamplerate support" ON)
option(AUBIO_DISABLE_JACK "Disable JACK support" ON)
option(AUBIO_DISABLE_FFTW3 "Disable FFTW3 support" ON)

# Enable simple wav file support
option(AUBIO_ENABLE_WAVREAD "Enable built-in WAV reader" ON)
option(AUBIO_ENABLE_WAVWRITE "Enable built-in WAV writer" ON)

# Get current directory and project root
get_filename_component(PROJECT_ROOT ${CMAKE_CURRENT_SOURCE_DIR} DIRECTORY)

# # Fetch aubio source code
# include(FetchContent)

# # Set aubio version to fetch
# set(AUBIO_VERSION "0.4.9")

# message(STATUS "Fetching aubio version: ${AUBIO_VERSION}")

# if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.24.0")
#     cmake_policy(SET CMP0135 NEW)
# endif()

# FetchContent_Declare(
#     aubio
#     URL "https://github.com/aubio/aubio/archive/refs/tags/${AUBIO_VERSION}.tar.gz"
#     URL_HASH "SHA256=d91de8e95f1e3bb4d91afe5b2b73fa07a3a8b6b6cfaec4b0e48fd9b6a04aa756"
# )

# FetchContent_MakeAvailable(aubio)

# # Configure aubio build
# set(aubio_SOURCE_DIR ${aubio_SOURCE_DIR})
# set(aubio_BINARY_DIR ${aubio_BINARY_DIR})

# Use local aubio source directory without downloading
set(aubio_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/aubio")
set(aubio_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/aubio_build")


# Create config.h for aubio
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/config.h.in
    ${aubio_BINARY_DIR}/src/config.h
)
# Define aubio source files based on the actual aubio source structure
set(AUBIO_SOURCES
    # Core files
    ${aubio_SOURCE_DIR}/src/fvec.c
    ${aubio_SOURCE_DIR}/src/cvec.c
    ${aubio_SOURCE_DIR}/src/lvec.c
    ${aubio_SOURCE_DIR}/src/fmat.c
    ${aubio_SOURCE_DIR}/src/mathutils.c
    ${aubio_SOURCE_DIR}/src/musicutils.c
    ${aubio_SOURCE_DIR}/src/vecutils.c
    
    # IO
    ${aubio_SOURCE_DIR}/src/io/source.c
    ${aubio_SOURCE_DIR}/src/io/sink.c
    ${aubio_SOURCE_DIR}/src/io/ioutils.c
)

# Add conditional source files based on features
if(AUBIO_ENABLE_WAVREAD)
    list(APPEND AUBIO_SOURCES ${aubio_SOURCE_DIR}/src/io/source_wavread.c)
endif()

if(AUBIO_ENABLE_WAVWRITE)
    list(APPEND AUBIO_SOURCES ${aubio_SOURCE_DIR}/src/io/sink_wavwrite.c)
endif()

if(AUBIO_ENABLE_ONSET)
    list(APPEND AUBIO_SOURCES
        ${aubio_SOURCE_DIR}/src/onset/onset.c
        ${aubio_SOURCE_DIR}/src/onset/peakpicker.c
    )
endif()

if(AUBIO_ENABLE_PITCH)
    list(APPEND AUBIO_SOURCES
        ${aubio_SOURCE_DIR}/src/pitch/pitch.c
        ${aubio_SOURCE_DIR}/src/pitch/pitchyin.c
        ${aubio_SOURCE_DIR}/src/pitch/pitchyinfast.c
        ${aubio_SOURCE_DIR}/src/pitch/pitchyinfft.c
        ${aubio_SOURCE_DIR}/src/pitch/pitchschmitt.c
        ${aubio_SOURCE_DIR}/src/pitch/pitchfcomb.c
        ${aubio_SOURCE_DIR}/src/pitch/pitchmcomb.c
        ${aubio_SOURCE_DIR}/src/pitch/pitchspecacf.c
    )
endif()

if(AUBIO_ENABLE_TEMPO)
    list(APPEND AUBIO_SOURCES
        ${aubio_SOURCE_DIR}/src/tempo/tempo.c
        ${aubio_SOURCE_DIR}/src/tempo/beattracking.c
    )
endif()

if(AUBIO_ENABLE_NOTES)
    list(APPEND AUBIO_SOURCES
        ${aubio_SOURCE_DIR}/src/notes/notes.c
    )
endif()

if(AUBIO_ENABLE_FFT)
    list(APPEND AUBIO_SOURCES
        ${aubio_SOURCE_DIR}/src/spectral/ooura_fft8g.c
        ${aubio_SOURCE_DIR}/src/spectral/fft.c
        ${aubio_SOURCE_DIR}/src/spectral/phasevoc.c
    )
endif()

if(AUBIO_ENABLE_MFCC)
    list(APPEND AUBIO_SOURCES
        ${aubio_SOURCE_DIR}/src/spectral/dct.c
        ${aubio_SOURCE_DIR}/src/spectral/dct_accelerate.c
        ${aubio_SOURCE_DIR}/src/spectral/dct_plain.c
        ${aubio_SOURCE_DIR}/src/spectral/dct_fftw.c
        ${aubio_SOURCE_DIR}/src/spectral/dct_ipp.c
        ${aubio_SOURCE_DIR}/src/spectral/dct_ooura.c
        ${aubio_SOURCE_DIR}/src/spectral/mfcc.c
        ${aubio_SOURCE_DIR}/src/spectral/specdesc.c
        ${aubio_SOURCE_DIR}/src/spectral/statistics.c
        ${aubio_SOURCE_DIR}/src/spectral/filterbank.c
        ${aubio_SOURCE_DIR}/src/spectral/filterbank_mel.c
    )
endif()

# Add spectral processing
list(APPEND AUBIO_SOURCES
    ${aubio_SOURCE_DIR}/src/spectral/awhitening.c
    ${aubio_SOURCE_DIR}/src/spectral/tss.c
)

# Add temporal processing
list(APPEND AUBIO_SOURCES
    ${aubio_SOURCE_DIR}/src/temporal/filter.c
    ${aubio_SOURCE_DIR}/src/temporal/biquad.c
    ${aubio_SOURCE_DIR}/src/temporal/a_weighting.c
    ${aubio_SOURCE_DIR}/src/temporal/c_weighting.c
    ${aubio_SOURCE_DIR}/src/temporal/resampler.c
)

# Add utils
list(APPEND AUBIO_SOURCES
    ${aubio_SOURCE_DIR}/src/utils/hist.c
    ${aubio_SOURCE_DIR}/src/utils/log.c
    ${aubio_SOURCE_DIR}/src/utils/parameter.c
    ${aubio_SOURCE_DIR}/src/utils/scale.c
    ${aubio_SOURCE_DIR}/src/utils/strutils.c
)

# Add synth
list(APPEND AUBIO_SOURCES
    ${aubio_SOURCE_DIR}/src/synth/sampler.c
    ${aubio_SOURCE_DIR}/src/synth/wavetable.c
)


# Create the aubio library
add_library(aubio SHARED ${AUBIO_SOURCES})


# Set library properties
set_target_properties(aubio PROPERTIES
    VERSION 5.0.0
    SOVERSION 5
)

# Include directories
target_include_directories(aubio PUBLIC
    ${aubio_SOURCE_DIR}/src
    ${aubio_BINARY_DIR}/src
)

# Compiler definitions
target_compile_definitions(aubio PRIVATE
    HAVE_CONFIG_H=1
)

# Platform-specific configurations
if(WIN32)
    set_target_properties(aubio PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
    # set_target_properties(aubio PROPERTIES
    #     LINK_FLAGS "/DEF:${aubio_SOURCE_DIR}/src/aubio.def"
    # )
    target_compile_definitions(aubio PRIVATE
        HAVE_WIN_HACKS=1
        _USE_MATH_DEFINES=1
    )
    target_link_libraries(aubio PRIVATE winmm)
endif()

if(ANDROID)
    target_link_libraries(aubio PRIVATE m log)
    if(ANDROID_ARM_NEON)
        target_compile_definitions(aubio PRIVATE HAVE_NEON=1)
    endif()
endif()

if(APPLE)
    if(IOS)
        target_link_libraries(aubio PRIVATE "-framework CoreFoundation" "-framework AudioToolbox")
        target_compile_definitions(aubio PRIVATE HAVE_SOURCE_APPLE_AUDIO=1)
    elseif(NOT IOS)
        target_link_libraries(aubio PRIVATE "-framework CoreFoundation" "-framework AudioToolbox" "-framework Accelerate")
        target_compile_definitions(aubio PRIVATE HAVE_SOURCE_APPLE_AUDIO=1 HAVE_ACCELERATE=1)
    endif()
endif()

if(UNIX AND NOT APPLE)
    target_link_libraries(aubio PRIVATE m)
endif()

# Installation
install(TARGETS aubio
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

# Install headers
install(FILES ${aubio_SOURCE_DIR}/src/aubio.h 
    DESTINATION include
)
