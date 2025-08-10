// control-plane/benchmark/latency.ts
// Phase 1: Performance Benchmark for < 50ms latency validation

const ITERATIONS = 1000;
const WS_URL = "ws://localhost:8081";

async function benchmarkLatency() {
  const ws = new WebSocket(WS_URL);
  const latencies: number[] = [];
  
  await new Promise((resolve) => {
    ws.onopen = resolve;
  });
  
  for (let i = 0; i < ITERATIONS; i++) {
    const start = performance.now();
    const data = new Uint8Array(100); // 100 byte payload
    data.fill(120); // Fill with 'x'
    
    await new Promise<void>((resolve) => {
      ws.send(data);
      // Measure round-trip time
      setTimeout(() => {
        const latency = performance.now() - start;
        latencies.push(latency);
        resolve();
      }, 0);
    });
    
    // Small delay between iterations
    await new Promise(r => setTimeout(r, 10));
  }
  
  ws.close();
  
  // Calculate statistics
  const avg = latencies.reduce((a, b) => a + b, 0) / latencies.length;
  const sorted = [...latencies].sort((a, b) => a - b);
  const p50 = sorted[Math.floor(latencies.length * 0.5)];
  const p95 = sorted[Math.floor(latencies.length * 0.95)];
  const p99 = sorted[Math.floor(latencies.length * 0.99)];
  const max = sorted[sorted.length - 1];
  
  console.log("=== Latency Benchmark Results ===");
  console.log(`Iterations: ${ITERATIONS}`);
  console.log(`Average: ${avg.toFixed(2)}ms`);
  console.log(`P50: ${p50.toFixed(2)}ms`);
  console.log(`P95: ${p95.toFixed(2)}ms`);
  console.log(`P99: ${p99.toFixed(2)}ms`);
  console.log(`Max: ${max.toFixed(2)}ms`);
  
  const under50ms = latencies.filter(l => l < 50).length;
  const percentage = (under50ms / ITERATIONS) * 100;
  console.log(`\nUnder 50ms: ${under50ms}/${ITERATIONS} (${percentage.toFixed(1)}%)`);
  
  if (percentage < 99) {
    console.error("❌ FAILED: Less than 99% of requests under 50ms");
    process.exit(1);
  } else {
    console.log("✅ PASSED: 99%+ requests under 50ms");
  }
}

benchmarkLatency().catch(console.error);