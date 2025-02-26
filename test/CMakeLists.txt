include_directories("./src/include")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-unused-parameter")
file(
  GLOB_RECURSE
  SOURCES
  ./*.cpp
  ../src/core/test/*.cpp
  ../src/gopt/test/*.cpp
  ../src/opr/test/*.cpp
  ../src/plugin/test/*.cpp
  ../src/serialization/test/*.cpp)
if(MGE_WITH_JIT)
  file(GLOB_RECURSE SOURCES_ ../src/jit/test/*.cpp)
  list(APPEND SOURCES ${SOURCES_})
endif()
if(MGE_WITH_DISTRIBUTED)
  file(GLOB_RECURSE SOURCES_ ../src/opr-mm/test/*.cpp)
  list(APPEND SOURCES ${SOURCES_})
endif()
if(MGE_WITH_CUDA AND MGE_WITH_TRT)
  file(GLOB_RECURSE SOURCES_ ../src/tensorrt/test/*.cpp)
  list(APPEND SOURCES ${SOURCES_})
endif()

add_executable(megbrain_test ${SOURCES})
if(WIN32 OR MSVC)
  target_compile_definitions(megbrain_test PRIVATE MGE_WINDOWS_STATIC_LINK)
endif()
target_link_libraries(megbrain_test gtest gmock)
target_link_libraries(megbrain_test megbrain megdnn ${MGE_CUDA_LIBS})
if(MGE_WITH_CUDA)
  target_include_directories(megbrain_test PRIVATE ${CUDNN_INCLUDE_DIR})
endif()
if(CXX_SUPPORT_WCLASS_MEMACCESS)
  if(MGE_WITH_CUDA)
    target_compile_options(
      megbrain_test
      PRIVATE "$<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=-Wno-class-memaccess>"
              "$<$<NOT:$<COMPILE_LANGUAGE:CUDA>>:-Wno-class-memaccess>")
  else()
    target_compile_options(megbrain_test PRIVATE "-Wno-class-memaccess")
  endif()
endif()

if(UNIX)
  if(APPLE OR ANDROID)
    target_link_libraries(megbrain_test dl)
  else()
    target_link_libraries(megbrain_test dl rt)
  endif()
endif()

if(MGE_WITH_DISTRIBUTED)
  target_link_libraries(megbrain_test megray)
endif()

if(MGE_WITH_JIT)
  if(MGE_WITH_JIT_MLIR)
    add_subdirectory(${PROJECT_SOURCE_DIR}/src/jit/test/mlir
                     ${CMAKE_CURRENT_BINARY_DIR}/../src/jit/test/mlir)
  endif()
endif()

install(
  TARGETS megbrain_test
  EXPORT ${MGE_EXPORT_TARGETS}
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
