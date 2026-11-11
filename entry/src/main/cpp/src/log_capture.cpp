/*
 * Copyright (C) 2026 MC4HOS Contributors
 * SPDX-License-Identifier: MPL-2.0
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#include "log_capture.h"

#include <unistd.h>
#include <cstdio>
#include <mutex>
#include <thread>
#include <vector>

namespace mc4hos::log {

namespace {

std::mutex g_mutex;
std::function<void(const char *)> g_sink;
FILE *g_logFile = nullptr;
bool g_installed = false;

void HandleLine(const std::string &line) {
    if (line.empty()) {
        return;
    }
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_logFile != nullptr) {
        std::fwrite(line.c_str(), 1, line.size(), g_logFile);
        std::fwrite("\n", 1, 1, g_logFile);
        std::fflush(g_logFile);
    }
    if (g_sink) {
        g_sink(line.c_str());
    }
}

void ReaderLoop(int readFd) {
    std::vector<char> buf;
    buf.reserve(4096);
    char chunk[4096];
    while (true) {
        ssize_t n = ::read(readFd, chunk, sizeof(chunk));
        if (n <= 0) {
            if (n < 0 && errno == EINTR) {
                continue;
            }
            break;
        }
        for (ssize_t i = 0; i < n; i++) {
            if (chunk[i] == '\n') {
                HandleLine(std::string(buf.begin(), buf.end()));
                buf.clear();
            } else if (chunk[i] != '\r') {
                buf.push_back(chunk[i]);
                if (buf.size() >= 8192) {
                    HandleLine(std::string(buf.begin(), buf.end()));
                    buf.clear();
                }
            }
        }
    }
    if (!buf.empty()) {
        HandleLine(std::string(buf.begin(), buf.end()));
    }
}

} // namespace

void Install(const std::string &logDir, std::function<void(const char *)> sink) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_installed) {
        return;
    }
    g_sink = std::move(sink);

    if (!logDir.empty()) {
        std::string path = logDir + (logDir.back() == '/' ? "" : "/") + "latest.log";
        g_logFile = std::fopen(path.c_str(), "a");
    }

    int fds[2];
    if (::pipe(fds) != 0) {
        return;
    }
    // Route process stdout/stderr into the pipe. hilog uses its own socket,
    // so launcher/system logging is unaffected.
    ::dup2(fds[1], STDOUT_FILENO);
    ::dup2(fds[1], STDERR_FILENO);
    ::close(fds[1]);
    g_installed = true;

    std::thread reader(ReaderLoop, fds[0]);
    reader.detach();
}

void Emit(const std::string &line) {
    HandleLine(line);
}

} // namespace mc4hos::log
