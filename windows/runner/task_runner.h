// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef PACKAGES_FLUTTER_LEDFX_TASK_RUNNER_H_
#define PACKAGES_FLUTTER_LEDFX_TASK_RUNNER_H_

#include <windows.h>

#include <chrono>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <functional>

using TaskClosure = std::function<void()>;

class TaskRunner
{
public:
    virtual void EnqueueTask(TaskClosure task) = 0;
    virtual ~TaskRunner() = default;
};

//   https://github.com/flutter/engine/blob/d7c0bcfe7a30408b0722c9d47d8b0b1e4cdb9c81/shell/platform/windows/task_runner_window.h
class TaskRunnerWindows : public TaskRunner
{
public:
    virtual void EnqueueTask(TaskClosure task);

    TaskRunnerWindows();
    ~TaskRunnerWindows();

private:
    void ProcessTasks();

    WNDCLASS RegisterWindowClass();

    LRESULT
    HandleMessage(UINT const message, WPARAM const wparam,
                  LPARAM const lparam) noexcept;

    static LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                    WPARAM const wparam,
                                    LPARAM const lparam) noexcept;

    HWND window_handle_;
    std::string window_class_name_;
    std::mutex tasks_mutex_;
    std::queue<TaskClosure> tasks_;

    // Prevent copying.
    TaskRunnerWindows(TaskRunnerWindows const &) = delete;
    TaskRunnerWindows &operator=(TaskRunnerWindows const &) = delete;
};

#endif // PACKAGES_FLUTTER_WEBRTC_TASK_RUNNER_H_