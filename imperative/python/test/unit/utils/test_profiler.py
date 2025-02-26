# -*- coding: utf-8 -*-
import json
import os
import tempfile

import pytest

from megengine import Parameter
from megengine import distributed as dist
from megengine import tensor
from megengine.jit import trace
from megengine.module import Module
from megengine.utils.profiler import Profiler, scope


class Simple(Module):
    def __init__(self):
        super().__init__()
        self.a = Parameter([1.23], dtype="float32")

    def forward(self, x):
        x = x * self.a
        return x


@pytest.mark.parametrize("format", ["chrome_timeline.json", "memory_flow.svg"])
@pytest.mark.parametrize(
    "trace_mode", [True, False, None], ids=["symbolic", "no-symbolic", "no-trace"]
)
@pytest.mark.require_ngpu(1)
def test_profiler(format, trace_mode):
    tempdir = tempfile.TemporaryDirectory()
    profile_prefix = tempdir.name
    profile_path = os.path.join(profile_prefix, "{}.{}".format(os.getpid(), format))

    def infer():
        with scope("my_scope"):
            oup = Simple()(tensor([1.23], dtype="float32"))
            return oup

    if trace_mode:
        infer = trace(symbolic=trace_mode)(infer)

    with Profiler(profile_prefix, format=format):
        infer()

    assert os.path.exists(profile_path), "profiling results not found"

    if format == "chrome_timeline.json":
        with open(profile_path, "r") as f:
            events = json.load(f)
        if isinstance(events, dict):
            assert "traceEvents" in events
            events = events["traceEvents"]
        prev_ts = {}
        scope_count = 0
        for event in events:
            if "dur" in event:
                assert event["dur"] >= 0
            elif "ts" in event and "tid" in event:
                ts = event["ts"]
                tid = event["tid"]
                if ts != 0:
                    assert (tid not in prev_ts) or prev_ts[tid] <= ts
                    prev_ts[tid] = ts
            if "name" in event and event["name"] == "my_scope":
                scope_count += 1
        assert scope_count > 0 and scope_count % 2 == 0


@pytest.mark.parametrize("format", ["chrome_timeline.json", "memory_flow.svg"])
@pytest.mark.parametrize(
    "trace_mode", [True, False, None], ids=["symbolic", "no-symbolic", "no-trace"]
)
@pytest.mark.isolated_distributed
@pytest.mark.require_ngpu(2)
def test_profiler_dist(format, trace_mode):
    n_gpus = 2
    tempdir = tempfile.TemporaryDirectory()
    profile_prefix = tempdir.name
    profile_path = os.path.join(profile_prefix, "{}.{}".format(os.getpid(), format))

    def infer():
        with scope("my_scope"):
            oup = Simple()(tensor([1.23], dtype="float32"))
            return oup

    if trace_mode:
        infer = trace(symbolic=trace_mode)(infer)

    @dist.launcher(n_gpus=2)
    def worker():
        infer()

    with Profiler(profile_prefix, format=format):
        worker()

    assert os.path.exists(profile_path), "profiling results not found"
    assert len(os.listdir(tempdir.name)) == n_gpus + 1
