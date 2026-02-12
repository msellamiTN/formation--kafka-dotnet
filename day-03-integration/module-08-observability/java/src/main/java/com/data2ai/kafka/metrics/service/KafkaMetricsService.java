package com.data2ai.kafka.metrics.service;

import org.apache.kafka.clients.admin.*;
import org.apache.kafka.clients.consumer.OffsetAndMetadata;
import org.apache.kafka.common.Node;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.TopicPartitionInfo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

/**
 * Service that queries Kafka AdminClient for cluster health,
 * consumer group lag, and topic metadata.
 */
@Service
public class KafkaMetricsService {

    private static final Logger log = LoggerFactory.getLogger(KafkaMetricsService.class);

    @Value("${spring.kafka.bootstrap-servers}")
    private String bootstrapServers;

    private AdminClient adminClient;

    @PostConstruct
    public void init() {
        Map<String, Object> config = new HashMap<>();
        config.put(AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        config.put(AdminClientConfig.REQUEST_TIMEOUT_MS_CONFIG, 5000);
        config.put(AdminClientConfig.DEFAULT_API_TIMEOUT_MS_CONFIG, 10000);
        adminClient = AdminClient.create(config);
    }

    @PreDestroy
    public void destroy() {
        if (adminClient != null) {
            adminClient.close(Duration.ofSeconds(5));
        }
    }

    /**
     * Get Kafka cluster health: broker count, controller, cluster ID.
     */
    public Map<String, Object> getClusterHealth() {
        Map<String, Object> result = new HashMap<>();
        try {
            DescribeClusterResult cluster = adminClient.describeCluster();
            Collection<Node> nodes = cluster.nodes().get(5, TimeUnit.SECONDS);
            Node controller = cluster.controller().get(5, TimeUnit.SECONDS);
            String clusterId = cluster.clusterId().get(5, TimeUnit.SECONDS);

            result.put("status", "HEALTHY");
            result.put("clusterId", clusterId);
            result.put("brokerCount", nodes.size());
            result.put("controllerId", controller.id());

            List<Map<String, Object>> brokers = new ArrayList<>();
            for (Node node : nodes) {
                brokers.add(Map.of(
                        "id", node.id(),
                        "host", node.host(),
                        "port", node.port(),
                        "rack", node.rack() != null ? node.rack() : "none"
                ));
            }
            result.put("brokers", brokers);
        } catch (Exception e) {
            log.error("Failed to get cluster health", e);
            result.put("status", "UNHEALTHY");
            result.put("error", e.getMessage());
        }
        return result;
    }

    /**
     * Get consumer groups with lag information.
     */
    public Map<String, Object> getConsumerGroups() {
        Map<String, Object> result = new HashMap<>();
        try {
            ListConsumerGroupsResult groupsResult = adminClient.listConsumerGroups();
            Collection<ConsumerGroupListing> groups = groupsResult.all().get(5, TimeUnit.SECONDS);

            List<Map<String, Object>> groupList = new ArrayList<>();
            for (ConsumerGroupListing group : groups) {
                Map<String, Object> groupInfo = new HashMap<>();
                groupInfo.put("groupId", group.groupId());
                groupInfo.put("isSimple", group.isSimpleConsumerGroup());

                try {
                    // Get offsets for this group
                    Map<TopicPartition, OffsetAndMetadata> offsets =
                            adminClient.listConsumerGroupOffsets(group.groupId())
                                    .partitionsToOffsetAndMetadata()
                                    .get(5, TimeUnit.SECONDS);

                    long totalLag = 0;
                    List<Map<String, Object>> partitions = new ArrayList<>();
                    if (!offsets.isEmpty()) {
                        // Get end offsets to calculate lag
                        Map<TopicPartition, ListOffsetsResult.ListOffsetsResultInfo> endOffsets =
                                adminClient.listOffsets(
                                        offsets.keySet().stream().collect(
                                                Collectors.toMap(tp -> tp, tp -> OffsetSpec.latest())
                                        )
                                ).all().get(5, TimeUnit.SECONDS);

                        for (Map.Entry<TopicPartition, OffsetAndMetadata> entry : offsets.entrySet()) {
                            TopicPartition tp = entry.getKey();
                            long committed = entry.getValue().offset();
                            long end = endOffsets.containsKey(tp) ? endOffsets.get(tp).offset() : committed;
                            long lag = end - committed;
                            totalLag += lag;

                            partitions.add(Map.of(
                                    "topic", tp.topic(),
                                    "partition", tp.partition(),
                                    "committedOffset", committed,
                                    "endOffset", end,
                                    "lag", lag
                            ));
                        }
                    }
                    groupInfo.put("totalLag", totalLag);
                    groupInfo.put("partitions", partitions);
                } catch (Exception e) {
                    groupInfo.put("error", "Could not fetch offsets: " + e.getMessage());
                }

                groupList.add(groupInfo);
            }

            result.put("count", groups.size());
            result.put("groups", groupList);
        } catch (Exception e) {
            log.error("Failed to get consumer groups", e);
            result.put("error", e.getMessage());
        }
        return result;
    }

    /**
     * Get topic metadata: name, partition count, replication factor.
     */
    public Map<String, Object> getTopics() {
        Map<String, Object> result = new HashMap<>();
        try {
            Set<String> topicNames = adminClient.listTopics().names().get(5, TimeUnit.SECONDS);

            Map<String, TopicDescription> descriptions =
                    adminClient.describeTopics(topicNames).allTopicNames().get(5, TimeUnit.SECONDS);

            List<Map<String, Object>> topics = new ArrayList<>();
            for (TopicDescription desc : descriptions.values()) {
                List<TopicPartitionInfo> partitions = desc.partitions();
                int replicationFactor = partitions.isEmpty() ? 0 : partitions.get(0).replicas().size();

                topics.add(Map.of(
                        "name", desc.name(),
                        "partitions", partitions.size(),
                        "replicationFactor", replicationFactor,
                        "internal", desc.isInternal()
                ));
            }

            topics.sort(Comparator.comparing(t -> (String) t.get("name")));
            result.put("count", topics.size());
            result.put("topics", topics);
        } catch (Exception e) {
            log.error("Failed to get topics", e);
            result.put("error", e.getMessage());
        }
        return result;
    }
}
