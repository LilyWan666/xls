// Copyright 2021 The XLS Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "xls/noc/drivers/experiment.h"

#include "absl/strings/str_format.h"
#include "xls/common/logging/logging.h"
#include "xls/noc/simulation/common.h"
#include "xls/noc/simulation/network_graph.h"
#include "xls/noc/simulation/network_graph_builder.h"
#include "xls/noc/simulation/noc_traffic_injector.h"
#include "xls/noc/simulation/parameters.h"
#include "xls/noc/simulation/sim_objects.h"
#include "xls/noc/simulation/simulator_to_traffic_injector_shim.h"
#include "xls/noc/simulation/traffic_description.h"

namespace xls::noc {

namespace internal {

std::vector<PacketInfo> GetPacketInfo(absl::Span<const TimedDataFlit> flits,
                                      int64_t vc_index) {
  std::vector<PacketInfo> packet_info;
  // collected_injection_time_from_head: When true, collected the injection time
  // from the head flit. Otherwise, collect the injection time from the tail
  // flit.
  bool collected_injection_time_from_head = false;
  for (const TimedDataFlit& flit : flits) {
    // filter by vc_index
    if (flit.flit.vc != vc_index) {
      continue;
    }
    // Using the head flit, get the injection clock cycle time.
    if (flit.flit.type == FlitType::kHead) {
      packet_info.emplace_back(PacketInfo());
      packet_info.back().injection_clock_cycle_time =
          flit.metadata.injection_cycle_time;
      collected_injection_time_from_head = true;
    }
    // Using the tail flit, get the arrival time.
    if (flit.flit.type == FlitType::kTail) {
      if (!collected_injection_time_from_head) {
        packet_info.emplace_back(PacketInfo());
        packet_info.back().injection_clock_cycle_time =
            flit.metadata.injection_cycle_time;
      }
      packet_info.back().arrival_clock_cycle_time = flit.cycle;
      collected_injection_time_from_head = false;
    }
  }
  return packet_info;
}

Stats GetStats(absl::Span<const PacketInfo> packets) {
  Stats result;
  if (packets.empty()) {
    return Stats();
  }
  int64_t sum = 0;
  int64_t& min_latency = result.min_latency;
  int64_t& max_latency = result.max_latency;
  int64_t& min_injection_cycle_time = result.min_injection_cycle_time;
  int64_t& max_injection_cycle_time = result.max_injection_cycle_time;
  int64_t& min_arrival_cycle_time = result.min_arrival_cycle_time;
  int64_t& max_arrival_cycle_time = result.max_arrival_cycle_time;
  for (const PacketInfo& packet : packets) {
    // injection_clock_cycle_time
    const int64_t& injection_clock_cycle_time =
        packet.injection_clock_cycle_time;
    min_injection_cycle_time =
        std::min(min_injection_cycle_time, injection_clock_cycle_time);
    max_injection_cycle_time =
        std::max(max_injection_cycle_time, injection_clock_cycle_time);
    // arrival_clock_cycle_time
    const int64_t& arrival_clock_cycle_time = packet.arrival_clock_cycle_time;
    min_arrival_cycle_time =
        std::min(min_arrival_cycle_time, arrival_clock_cycle_time);
    max_arrival_cycle_time =
        std::max(max_arrival_cycle_time, arrival_clock_cycle_time);
    // latency
    int64_t latency = arrival_clock_cycle_time - injection_clock_cycle_time;
    min_latency = std::min(min_latency, latency);
    max_latency = std::max(max_latency, latency);
    sum += latency;
  }
  result.average_latency =
      static_cast<double>(sum) / static_cast<double>(packets.size());
  return result;
}
}  // namespace internal

absl::Status ExperimentMetrics::DebugDump() const {
  XLS_LOG(INFO) << "Dumping Metrics ...";

  for (auto& [name, val] : float_metrics_) {
    XLS_LOG(INFO) << absl::StreamFormat("%s : %g", name, val);
  }

  for (auto& [name, val] : integer_metrics_) {
    XLS_LOG(INFO) << absl::StreamFormat("%s : %g", name, val);
  }

  return absl::OkStatus();
}

absl::StatusOr<ExperimentMetrics> ExperimentRunner::RunExperiment(
    const ExperimentConfig& experiment_config) const {
  // Build and assign simulation objects.
  NetworkManager graph;
  NocParameters params;

  XLS_RETURN_IF_ERROR(BuildNetworkGraphFromProto(
      experiment_config.GetNetworkConfig(), &graph, &params));

  // Create global routing table.
  DistributedRoutingTableBuilderForTrees route_builder;
  XLS_ASSIGN_OR_RETURN(DistributedRoutingTable routing_table,
                       route_builder.BuildNetworkRoutingTables(
                           graph.GetNetworkIds()[0], graph, params));

  // Build traffic model.
  RandomNumberInterface rnd;
  rnd.SetSeed(seed_);

  const NocTrafficManager& traffic_manager =
      experiment_config.GetTrafficConfig();
  XLS_ASSIGN_OR_RETURN(TrafficModeId mode_id,
                       traffic_manager.GetTrafficModeIdByName(mode_name_));
  XLS_ASSIGN_OR_RETURN(
      NocTrafficInjector traffic_injector,
      NocTrafficInjectorBuilder().Build(
          cycle_time_in_ps_, mode_id,
          routing_table.GetSourceIndices().GetNetworkComponents(),
          routing_table.GetSinkIndices().GetNetworkComponents(),
          params.GetNetworkParam(graph.GetNetworkIds()[0])
              ->GetVirtualChannels(),
          traffic_manager, graph, params, rnd));

  // Build simulator objects.
  NocSimulator simulator;
  XLS_RET_CHECK_OK(simulator.Initialize(graph, params, routing_table,
                                        graph.GetNetworkIds()[0]));
  simulator.Dump();

  // Hook traffic injector and simulator together.
  NocSimulatorToNocTrafficInjectorShim injector_shim(simulator,
                                                     traffic_injector);
  traffic_injector.SetSimulatorShim(injector_shim);
  simulator.RegisterPreCycleService(injector_shim);

  // Run simulation.
  for (int64_t i = 0; i < total_simulation_cycle_count_; ++i) {
    XLS_RET_CHECK_OK(simulator.RunCycle());
  }

  // Obtain metrics.  For now, the runner will measure traffic rate
  // for each flow, and sink. It will also collect the latency metrics from the
  // sink.
  //
  // TODO(tedhong): 2021-07-13 Factor this out to make it possible for
  //                each experiment to define the set of metrics needed.
  ExperimentMetrics metrics;

  for (int64_t i = 0; i < traffic_injector.FlowCount(); ++i) {
    TrafficFlowId flow_id = traffic_injector.GetTrafficFlows().at(i);

    std::string metric_name =
        absl::StrFormat("Flow:%s:TrafficRateInMiBps",
                        traffic_manager.GetTrafficFlow(flow_id).GetName());

    double traffic_rate =
        traffic_injector.MeasuredTrafficRateInMiBps(cycle_time_in_ps_, i);

    metrics.SetFloatMetric(metric_name, traffic_rate);
  }

  for (NetworkComponentId sink_id :
       routing_table.GetSinkIndices().GetNetworkComponents()) {
    XLS_ASSIGN_OR_RETURN(NetworkComponentParam nc_param,
                         params.GetNetworkComponentParam(sink_id));
    XLS_CHECK(absl::holds_alternative<NetworkInterfaceSinkParam>(nc_param));
    std::string nc_name =
        std::string(absl::get<NetworkInterfaceSinkParam>(nc_param).GetName());

    std::string metric_name =
        absl::StrFormat("Sink:%s:TrafficRateInMiBps", nc_name);

    XLS_ASSIGN_OR_RETURN(SimNetworkInterfaceSink * sink,
                         simulator.GetSimNetworkInterfaceSink(sink_id));

    double traffic_rate = sink->MeasuredTrafficRateInMiBps(cycle_time_in_ps_);
    metrics.SetFloatMetric(metric_name, traffic_rate);

    metric_name = absl::StrFormat("Sink:%s:FlitCount", nc_name);
    metrics.SetIntegerMetric(metric_name, sink->GetReceivedTraffic().size());

    // Latency stats
    const internal::Stats stats =
        GetStats(internal::GetPacketInfo(sink->GetReceivedTraffic(), 0));
    metric_name = absl::StrFormat("Sink:%s:MinimumInjectionTime", nc_name);
    metrics.SetIntegerMetric(metric_name, stats.min_injection_cycle_time);
    metric_name = absl::StrFormat("Sink:%s:MaximumInjectionTime", nc_name);
    metrics.SetIntegerMetric(metric_name, stats.max_injection_cycle_time);
    metric_name = absl::StrFormat("Sink:%s:MinimumArrivalTime", nc_name);
    metrics.SetIntegerMetric(metric_name, stats.min_arrival_cycle_time);
    metric_name = absl::StrFormat("Sink:%s:MaximumArrivalTime", nc_name);
    metrics.SetIntegerMetric(metric_name, stats.max_arrival_cycle_time);
    metric_name = absl::StrFormat("Sink:%s:MinimumLatency", nc_name);
    metrics.SetIntegerMetric(metric_name, stats.min_latency);
    metric_name = absl::StrFormat("Sink:%s:MaximumLatency", nc_name);
    metrics.SetIntegerMetric(metric_name, stats.max_latency);
    metric_name = absl::StrFormat("Sink:%s:AverageLatency", nc_name);
    metrics.SetFloatMetric(metric_name, stats.average_latency);

    // Per VC Metrics
    int64_t vc_count =
        params.GetNetworkParam(graph.GetNetworkIds()[0])->VirtualChannelCount();
    for (int64_t vc = 0; vc < vc_count; ++vc) {
      metric_name =
          absl::StrFormat("Sink:%s:VC:%d:TrafficRateInMiBps", nc_name, vc);
      traffic_rate = sink->MeasuredTrafficRateInMiBps(cycle_time_in_ps_, vc);
      metrics.SetFloatMetric(metric_name, traffic_rate);
    }
  }

  // Get Utilization of the routers.
  for (const SimInputBufferedVCRouter& router : simulator.GetRouters()) {
    XLS_ASSIGN_OR_RETURN(
        NetworkComponentParam param,
        simulator.GetNocParameters()->GetNetworkComponentParam(router.GetId()));
    RouterParam router_param = absl::get<RouterParam>(param);
    router_param.GetName();
    std::string metric_name =
        absl::StrFormat("Router:%s:Utilization", router_param.GetName());
    metrics.SetFloatMetric(
        metric_name, static_cast<double>(router.GetUtilizationCycleCount()) /
                         static_cast<double>(total_simulation_cycle_count_));
  }

  return metrics;
}

}  // namespace xls::noc