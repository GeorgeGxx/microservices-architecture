import asyncio
import logging
from typing import Dict, Any, List
from langchain_core.messages import HumanMessage
from app.agents.graph import ecommerce_agent_app

logger = logging.getLogger("observability_evals")

GOLDEN_EVAL_DATASET = [
    {
        "query": "Where is my package with order ORD-1001?",
        "expected_agent": "order_support",
        "expected_substrings": ["ORD-1001", "DHL"]
    },
    {
        "query": "I need a powerful, lightweight laptop for video editing and programming.",
        "expected_agent": "product_advisor",
        "expected_substrings": ["MacBook", "M3"]
    },
    {
        "query": "How many days do I have to return an item, and what is the warranty policy?",
        "expected_agent": "policy_faq",
        "expected_substrings": ["30", "warranty", "days"]
    },
    {
        "query": "I want to request a refund of $120.00 dollars for order ORD-1002.",
        "expected_agent": "order_support",
        "expected_hitl": True,
        "expected_substrings": ["supervisor", "refund"]
    }
]


async def run_evaluations() -> Dict[str, Any]:
    logger.info("Running Microservices AI Copilot Evals...")

    total_tests = len(GOLDEN_EVAL_DATASET)
    passed = 0
    results: List[Dict[str, Any]] = []

    for idx, test_case in enumerate(GOLDEN_EVAL_DATASET, start=1):
        query = test_case["query"]
        expected_agent = test_case["expected_agent"]
        expected_hitl = test_case.get("expected_hitl", False)

        thread_config = {"configurable": {"thread_id": f"eval-thread-{idx}"}}
        state_input = {
            "messages": [HumanMessage(content=query)],
            "current_agent": "supervisor",
            "hitl_pending": False,
            "tool_calls": [],
            "hitl_payload": None,
            "final_output": None
        }

        result_state = await ecommerce_agent_app.ainvoke(state_input, config=thread_config)
        actual_agent = result_state.get("current_agent")
        actual_hitl = result_state.get("hitl_pending", False)
        final_text = result_state.get("final_output", "")

        agent_match = (actual_agent == expected_agent)
        hitl_match = (actual_hitl == expected_hitl)
        content_match = any(sub.lower() in final_text.lower() for sub in test_case["expected_substrings"])

        is_success = agent_match and hitl_match and content_match
        if is_success:
            passed += 1

        eval_row = {
            "case_id": idx,
            "query": query,
            "expected_agent": expected_agent,
            "actual_agent": actual_agent,
            "hitl_gate_correct": hitl_match,
            "content_verified": content_match,
            "status": "PASS" if is_success else "FAIL"
        }
        results.append(eval_row)
        logger.info("[%s] Test #%d: %s... -> Agent: %s (HITL: %s)", eval_row['status'], idx, query[:40], actual_agent, actual_hitl)

    score_pct = (passed / total_tests) * 100
    summary = {
        "total_evals": total_tests,
        "passed": passed,
        "score_percentage": f"{score_pct:.1f}%",
        "details": results
    }
    logger.info("Eval Run Summary: %d/%d passed (%.1f%%)", passed, total_tests, score_pct)
    return summary


if __name__ == "__main__":
    asyncio.run(run_evaluations())
