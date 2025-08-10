// control-plane/test/api.test.ts
import { expect, test, describe } from "bun:test";

const API_BASE = "http://localhost:3000/api";

describe("Control Plane API", () => {
  test("Health check", async () => {
    const res = await fetch(`${API_BASE}/health`);
    expect(res.status).toBe(200);
    
    const data = await res.json();
    expect(data.status).toBe("healthy");
  });
  
  test("Create session", async () => {
    const res = await fetch(`${API_BASE}/sessions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        userId: "test-user",
        workspace: "/tmp/test-workspace",
      }),
    });
    
    expect(res.status).toBe(200);
    
    const session = await res.json();
    expect(session.id).toBeDefined();
    expect(session.userId).toBe("test-user");
    expect(session.workspace).toBe("/tmp/test-workspace");
  });
  
  test("Get session", async () => {
    // First create a session
    const createRes = await fetch(`${API_BASE}/sessions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        userId: "test-user",
        workspace: "/tmp/test-workspace",
      }),
    });
    
    const { id } = await createRes.json();
    
    // Then get it
    const getRes = await fetch(`${API_BASE}/sessions/${id}`);
    expect(getRes.status).toBe(200);
    
    const session = await getRes.json();
    expect(session.id).toBe(id);
  });
});