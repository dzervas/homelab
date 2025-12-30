#!/usr/bin/env python3
"""Prometheus exporter for cliproxyapi usage metrics."""

import logging
import os
import time

import requests
from prometheus_client import GC_COLLECTOR, PLATFORM_COLLECTOR, PROCESS_COLLECTOR
from prometheus_client import REGISTRY, start_http_server
from prometheus_client.core import GaugeMetricFamily
from prometheus_client.registry import Collector

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)
log = logging.getLogger(__name__)

# Disable default collectors
REGISTRY.unregister(GC_COLLECTOR)
REGISTRY.unregister(PLATFORM_COLLECTOR)
REGISTRY.unregister(PROCESS_COLLECTOR)

# Configuration from environment
CLIPROXYAPI_URL = os.environ.get("CLIPROXYAPI_URL", "http://cliproxyapi:8317")
CLIPROXYAPI_TOKEN = os.environ.get("CLIPROXYAPI_TOKEN", "")
EXPORTER_PORT = int(os.environ.get("EXPORTER_PORT", "9090"))
REQUEST_TIMEOUT = int(os.environ.get("REQUEST_TIMEOUT", "30"))


def fetch_usage():
    """Fetch usage data from cliproxyapi."""
    headers = {"Authorization": f"Bearer {CLIPROXYAPI_TOKEN}"}
    url = f"{CLIPROXYAPI_URL}/v0/management/usage"

    resp = requests.get(url, headers=headers, timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()
    return resp.json()


class CliproxyCollector(Collector):
    """Collector that fetches metrics on scrape."""

    def collect(self):
        if not CLIPROXYAPI_TOKEN:
            raise RuntimeError("CLIPROXYAPI_TOKEN environment variable is required")

        data = fetch_usage()
        usage = data.get("usage", {})

        failed_requests = GaugeMetricFamily(
            "cliproxyapi_failed_requests_total",
            "Total number of failed requests",
        )
        failed_requests.add_metric([], data.get("failed_requests", 0))
        yield failed_requests

        total_requests = GaugeMetricFamily(
            "cliproxyapi_requests_total",
            "Total number of requests",
            labels=["status"],
        )
        total_requests.add_metric(["success"], usage.get("success_count", 0))
        total_requests.add_metric(["failure"], usage.get("failure_count", 0))
        yield total_requests

        total_tokens = GaugeMetricFamily(
            "cliproxyapi_tokens_total",
            "Total number of tokens used",
        )
        total_tokens.add_metric([], usage.get("total_tokens", 0))
        yield total_tokens

        model_requests = GaugeMetricFamily(
            "cliproxyapi_model_requests_total",
            "Total requests per model",
            labels=["api", "model"],
        )
        model_requests_failed = GaugeMetricFamily(
            "cliproxyapi_model_requests_failed_total",
            "Failed requests per model",
            labels=["api", "model"],
        )
        model_tokens = GaugeMetricFamily(
            "cliproxyapi_model_tokens_total",
            "Total tokens per model by type",
            labels=["api", "model", "token_type"],
        )

        source_requests = GaugeMetricFamily(
            "cliproxyapi_source_requests_total",
            "Requests per source and model",
            labels=["source", "api", "model"],
        )
        source_requests_failed = GaugeMetricFamily(
            "cliproxyapi_source_requests_failed_total",
            "Failed requests per source and model",
            labels=["source", "api", "model"],
        )
        source_tokens = GaugeMetricFamily(
            "cliproxyapi_source_tokens_total",
            "Tokens per source and model by type",
            labels=["source", "api", "model", "token_type"],
        )

        apis = usage.get("apis", {})
        for api_name, api_data in apis.items():
            models = api_data.get("models", {})
            for model_name, model_data in models.items():
                model_requests.add_metric(
                    [api_name, model_name], model_data.get("total_requests", 0)
                )
                model_tokens.add_metric(
                    [api_name, model_name, "total"],
                    model_data.get("total_tokens", 0),
                )

                source_agg: dict[str, dict] = {}
                model_token_types = {
                    "input_tokens": 0,
                    "output_tokens": 0,
                    "reasoning_tokens": 0,
                    "cached_tokens": 0,
                }
                model_failed_count = 0

                for detail in model_data.get("details", []):
                    source = detail.get("source", "unknown")
                    tokens = detail.get("tokens", {})
                    is_failed = detail.get("failed", False)

                    if is_failed:
                        model_failed_count += 1

                    if source not in source_agg:
                        source_agg[source] = {
                            "requests": 0,
                            "failed": 0,
                            "input_tokens": 0,
                            "output_tokens": 0,
                            "reasoning_tokens": 0,
                            "cached_tokens": 0,
                        }

                    source_agg[source]["requests"] += 1
                    if is_failed:
                        source_agg[source]["failed"] += 1

                    for token_type in model_token_types:
                        val = tokens.get(token_type, 0)
                        model_token_types[token_type] += val
                        source_agg[source][token_type] += val

                model_requests_failed.add_metric(
                    [api_name, model_name], model_failed_count
                )
                for token_type, val in model_token_types.items():
                    model_tokens.add_metric([api_name, model_name, token_type], val)

                for source, agg in source_agg.items():
                    source_requests.add_metric(
                        [source, api_name, model_name], agg["requests"]
                    )
                    source_requests_failed.add_metric(
                        [source, api_name, model_name], agg["failed"]
                    )
                    for token_type in [
                        "input_tokens",
                        "output_tokens",
                        "reasoning_tokens",
                        "cached_tokens",
                    ]:
                        source_tokens.add_metric(
                            [source, api_name, model_name, token_type],
                            agg[token_type],
                        )

        yield model_requests
        yield model_requests_failed
        yield model_tokens
        yield source_requests
        yield source_requests_failed
        yield source_tokens


def main():
    """Main entry point."""
    log.info("Starting cliproxyapi exporter on port %d", EXPORTER_PORT)
    REGISTRY.register(CliproxyCollector())
    start_http_server(EXPORTER_PORT)

    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
