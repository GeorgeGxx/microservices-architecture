import React, { useState, useRef, useEffect } from 'react';
import { Bot, X, Send, Sparkles } from 'lucide-react';
import { HITLWidget } from './HITLWidget';

interface Message {
  id: string;
  sender: 'user' | 'agent';
  content: string;
  agentName?: string;
  timestamp: string;
  hitlPending?: boolean;
  hitlPayload?: any;
}

export const AICopilot: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);
  const [messages, setMessages] = useState<Message[]>([
    {
      id: 'welcome',
      sender: 'agent',
      content: 'Hello! I am your AI Shopping Copilot powered by **LangGraph** and **MCP** tools.\n\nI can help you with:\n- 📦 **DHL Tracking** (e.g. `ORD-1001` or `1`)\n- 🔍 **Product Catalog Recommendations via RAG**\n- 🛡️ **Store Return & Warranty Policies**\n- 💰 **Automated & Supervisor-Approved Refunds**',
      agentName: 'Supervisor Router',
      timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    }
  ]);
  const [input, setInput] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (isOpen) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages, isOpen, isLoading]);

  const handleSendMessage = async (text: string) => {
    if (!text.trim() || isLoading) return;

    const userMsg: Message = {
      id: `user-${Date.now()}`,
      sender: 'user',
      content: text,
      timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    };

    setMessages((prev) => [...prev, userMsg]);
    setInput('');
    setIsLoading(true);

    try {
      const res = await fetch('/api/ai/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: text, thread_id: 'session-copilot-spa' })
      });

      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();

      const agentMsg: Message = {
        id: `agent-${Date.now()}`,
        sender: 'agent',
        content: data.reply,
        agentName: data.active_agent,
        hitlPending: data.hitl_pending,
        hitlPayload: data.hitl_payload,
        timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
      };

      setMessages((prev) => [...prev, agentMsg]);
    } catch {
      const fallbackMsg: Message = {
        id: `agent-fallback-${Date.now()}`,
        sender: 'agent',
        content: `Received your inquiry: "${text}". The background AI service is currently initializing. You can browse products directly in the store catalog or verify that 'ai-service' is active on port 8010.`,
        agentName: 'Local Fallback Agent',
        timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
      };
      setMessages((prev) => [...prev, fallbackMsg]);
    } finally {
      setIsLoading(false);
    }
  };

  const handleHITLResolved = (ticketId: string, action: 'APPROVE' | 'REJECT') => {
    const confirmationMsg: Message = {
      id: `system-${Date.now()}`,
      sender: 'agent',
      content: `✅ **Supervisor Gate Update**: Action for ticket \`${ticketId}\` was **${action === 'APPROVE' ? 'APPROVED' : 'DENIED'}** by the human supervisor in StateGraph.`,
      agentName: 'HITL Supervisor Gate',
      timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    };
    setMessages((prev) => [...prev, confirmationMsg]);
  };

  const samplePrompts = [
    { label: '📦 Track DHL ORD-1001', prompt: 'What is the shipping status of my order ORD-1001?' },
    { label: '💻 Recommend Laptop', prompt: 'Recommend a high-performance laptop for software development and design.' },
    { label: '⚠️ Request Refund (HITL)', prompt: 'I would like to request a refund of $120.00 USD for order ORD-1002.' },
    { label: '📜 Return Policies', prompt: 'What are the return, warranty, and refund policies of the store?' }
  ];

  return (
    <>
      {/* Floating Action Button */}
      {!isOpen && (
        <button
          onClick={() => setIsOpen(true)}
          className="fixed bottom-6 right-6 z-40 flex items-center gap-2.5 px-4 py-3 rounded-full bg-gradient-to-r from-indigo-600 to-purple-600 hover:from-indigo-500 hover:to-purple-500 text-white font-medium shadow-xl shadow-indigo-600/30 hover:scale-105 active:scale-95 transition-all duration-200 border border-indigo-400/30"
          aria-label="Open AI Copilot"
        >
          <div className="relative">
            <Bot className="h-5 w-5" />
            <span className="absolute -top-1 -right-1 h-2.5 w-2.5 bg-emerald-400 rounded-full animate-ping"></span>
            <span className="absolute -top-1 -right-1 h-2.5 w-2.5 bg-emerald-400 rounded-full"></span>
          </div>
          <span className="text-sm font-semibold tracking-wide hidden sm:inline">AI Copilot</span>
        </button>
      )}

      {/* Slide-over Chat Drawer */}
      {isOpen && (
        <div className="fixed inset-y-0 right-0 z-50 w-full sm:w-[440px] md:w-[480px] bg-slate-950 border-l border-slate-800 shadow-2xl flex flex-col transition-all duration-300">
          {/* Header */}
          <div className="px-5 py-4 border-b border-slate-800 bg-slate-900/90 flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="h-9 w-9 rounded-xl bg-gradient-to-tr from-indigo-600 to-purple-600 flex items-center justify-center text-white shadow-md">
                <Bot className="h-5 w-5" />
              </div>
              <div>
                <div className="flex items-center gap-2">
                  <h3 className="font-bold text-sm text-white">AI Copilot</h3>
                  <span className="text-[10px] px-2 py-0.5 rounded-full bg-indigo-500/10 text-indigo-400 font-mono border border-indigo-500/20">
                    LangGraph + MCP
                  </span>
                </div>
                <p className="text-[11px] text-slate-400">Integrated Microservices Assistant</p>
              </div>
            </div>

            <button
              onClick={() => setIsOpen(false)}
              className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition"
              aria-label="Close Copilot"
            >
              <X className="h-5 w-5" />
            </button>
          </div>

          {/* Quick suggestions */}
          <div className="px-4 py-2 border-b border-slate-800/60 bg-slate-900/50 flex items-center gap-2 overflow-x-auto scrollbar-none text-xs">
            <span className="text-slate-500 flex items-center gap-1 shrink-0">
              <Sparkles className="h-3 w-3 text-indigo-400" /> Shortcuts:
            </span>
            {samplePrompts.map((sp) => (
              <button
                key={sp.label}
                onClick={() => void handleSendMessage(sp.prompt)}
                disabled={isLoading}
                className="whitespace-nowrap px-2.5 py-1 rounded-full bg-slate-800/80 hover:bg-slate-700 border border-slate-700/60 text-slate-300 hover:text-white transition text-[11px] disabled:opacity-40"
              >
                {sp.label}
              </button>
            ))}
          </div>

          {/* Message List */}
          <div className="flex-1 overflow-y-auto p-4 space-y-4">
            {messages.map((msg) => (
              <div
                key={msg.id}
                className={`flex gap-2.5 ${msg.sender === 'user' ? 'justify-end' : 'justify-start'}`}
              >
                {msg.sender === 'agent' && (
                  <div className="h-7 w-7 rounded-lg bg-indigo-600/20 border border-indigo-500/30 flex items-center justify-center text-indigo-400 shrink-0 mt-0.5">
                    <Bot className="h-3.5 w-3.5" />
                  </div>
                )}

                <div
                  className={`max-w-[85%] rounded-2xl p-3.5 text-xs sm:text-sm leading-relaxed ${
                    msg.sender === 'user'
                      ? 'bg-indigo-600 text-white rounded-br-none shadow-md shadow-indigo-600/10'
                      : 'bg-slate-900 border border-slate-800 text-slate-200 rounded-bl-none'
                  }`}
                >
                  {msg.agentName && (
                    <div className="flex items-center gap-1.5 mb-1.5 pb-1 border-b border-slate-800/80 text-[10px] font-mono text-indigo-400">
                      <span className="h-1.5 w-1.5 rounded-full bg-emerald-400"></span>
                      <span>{msg.agentName}</span>
                    </div>
                  )}

                  <div className="whitespace-pre-wrap">{msg.content}</div>

                  {msg.hitlPending && msg.hitlPayload && (
                    <HITLWidget payload={msg.hitlPayload} onResolved={handleHITLResolved} />
                  )}

                  <div className="mt-1.5 text-[9px] text-right opacity-50">
                    {msg.timestamp}
                  </div>
                </div>
              </div>
            ))}

            {isLoading && (
              <div className="flex gap-2.5 justify-start">
                <div className="h-7 w-7 rounded-lg bg-indigo-600/20 border border-indigo-500/30 flex items-center justify-center text-indigo-400 shrink-0 animate-pulse">
                  <Bot className="h-3.5 w-3.5" />
                </div>
                <div className="bg-slate-900 border border-slate-800 rounded-2xl rounded-bl-none p-3 text-xs text-slate-400 flex items-center gap-2">
                  <span className="h-2 w-2 rounded-full bg-indigo-500 animate-ping"></span>
                  <span>Querying microservices & local models...</span>
                </div>
              </div>
            )}

            <div ref={messagesEndRef} />
          </div>

          {/* Input Footer */}
          <form
            onSubmit={(e) => {
              e.preventDefault();
              void handleSendMessage(input);
            }}
            className="p-3 border-t border-slate-800 bg-slate-900/90 flex gap-2"
          >
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Ask about products, orders, shipping, or returns..."
              disabled={isLoading}
              className="flex-1 bg-slate-950 border border-slate-800 focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 rounded-xl px-3.5 py-2.5 text-xs sm:text-sm text-slate-100 placeholder-slate-500 outline-none transition"
            />
            <button
              type="submit"
              disabled={!input.trim() || isLoading}
              className="bg-indigo-600 hover:bg-indigo-500 text-white px-4 rounded-xl flex items-center justify-center transition disabled:opacity-40"
            >
              <Send className="h-4 w-4" />
            </button>
          </form>
        </div>
      )}
    </>
  );
};
