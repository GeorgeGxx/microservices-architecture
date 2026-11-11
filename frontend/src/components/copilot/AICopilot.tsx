import React, { useState, useRef, useEffect, useCallback } from 'react';
import { Bot, X, Send, Sparkles, PanelLeft, PanelRight } from 'lucide-react';
import { HITLWidget } from './HITLWidget';
import { useCart } from '../../context/CartContext';
import { useNotifications } from '../../context/NotificationContext';

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
  const { isCartOpen, setIsCartOpen } = useCart();
  const { isDrawerOpen, setIsDrawerOpen } = useNotifications();

  const [isOpen, setIsOpen] = useState(false);
  const [dockSide, setDockSide] = useState<'left' | 'right'>(() => {
    try {
      const saved = localStorage.getItem('copilot_dock_side');
      return saved === 'right' ? 'right' : 'left';
    } catch {
      return 'left';
    }
  });

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

  // Close Copilot if Cart or Notification drawer opens and they conflict (same side or narrow viewport)
  useEffect(() => {
    if ((isCartOpen || isDrawerOpen) && isOpen) {
      const isNarrowScreen = typeof window !== 'undefined' && window.innerWidth < 1024;
      if (dockSide === 'right' || isNarrowScreen) {
        setIsOpen(false);
      }
    }
  }, [isCartOpen, isDrawerOpen, dockSide, isOpen]);

  const handleOpenCopilot = useCallback(() => {
    const isNarrowScreen = typeof window !== 'undefined' && window.innerWidth < 1024;
    if (dockSide === 'right' || isNarrowScreen) {
      setIsCartOpen(false);
      setIsDrawerOpen(false);
    }
    setIsOpen(true);
  }, [dockSide, setIsCartOpen, setIsDrawerOpen]);

  const toggleDockSide = useCallback(() => {
    const nextSide = dockSide === 'left' ? 'right' : 'left';
    setDockSide(nextSide);
    try {
      localStorage.setItem('copilot_dock_side', nextSide);
    } catch {
      // ignore storage errors
    }
    if (nextSide === 'right' && (isCartOpen || isDrawerOpen)) {
      setIsCartOpen(false);
      setIsDrawerOpen(false);
    }
  }, [dockSide, isCartOpen, isDrawerOpen, setIsCartOpen, setIsDrawerOpen]);

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
          onClick={handleOpenCopilot}
          className={`fixed bottom-5 ${
            dockSide === 'left' ? 'left-5' : 'right-5'
          } z-40 group flex items-center gap-2 px-3 py-2 rounded-2xl bg-slate-900/95 hover:bg-slate-800 text-slate-200 hover:text-white backdrop-blur-md shadow-xl shadow-indigo-950/40 border border-slate-700/70 hover:border-indigo-400/60 hover:scale-105 active:scale-95 transition-all duration-200`}
          aria-label="Open AI Copilot"
        >
          <div className="relative w-6 h-6 rounded-xl bg-gradient-to-tr from-indigo-600 via-indigo-500 to-purple-600 flex items-center justify-center text-white shadow-sm shadow-indigo-500/40">
            <Bot className="h-3.5 w-3.5" />
            <span className="absolute -top-0.5 -right-0.5 h-2 w-2 bg-emerald-400 rounded-full animate-ping"></span>
            <span className="absolute -top-0.5 -right-0.5 h-2 w-2 bg-emerald-400 rounded-full"></span>
          </div>
          <div className="hidden sm:flex flex-col text-left pr-0.5">
            <span className="text-xs font-bold leading-tight tracking-tight text-white group-hover:text-indigo-200 transition-colors">
              Copilot
            </span>
            <span className="text-[9px] font-mono leading-none text-indigo-400">
              LangGraph
            </span>
          </div>
        </button>
      )}

      {/* Floating Chat Widget Window */}
      {isOpen && (
        <div
          className={`fixed inset-x-0 bottom-0 max-sm:h-[85vh] max-sm:rounded-t-2xl sm:inset-x-auto sm:bottom-6 ${
            dockSide === 'left' ? 'sm:left-6' : 'sm:right-6'
          } z-50 w-full sm:w-[360px] md:w-[380px] sm:h-[520px] sm:max-h-[calc(100vh-120px)] bg-slate-950/95 backdrop-blur-xl sm:rounded-2xl border border-slate-800/90 shadow-2xl shadow-indigo-950/40 flex flex-col transition-all duration-200 overflow-hidden`}
        >
          {/* Header */}
          <div className="px-3.5 py-2.5 border-b border-slate-800/80 bg-slate-900/90 backdrop-blur-md flex items-center justify-between">
            <div className="flex items-center gap-2.5">
              <div className="h-7 w-7 rounded-lg bg-gradient-to-tr from-indigo-600 to-purple-600 flex items-center justify-center text-white shadow-sm shadow-indigo-500/30">
                <Bot className="h-4 w-4" />
              </div>
              <div>
                <div className="flex items-center gap-1.5">
                  <h3 className="font-bold text-xs text-white">AI Copilot</h3>
                  <span className="text-[9px] px-1.5 py-0.5 rounded bg-indigo-500/10 text-indigo-400 font-mono border border-indigo-500/20">
                    LangGraph + MCP
                  </span>
                </div>
                <p className="text-[10px] text-slate-400 leading-tight">Store Assistant</p>
              </div>
            </div>

            <div className="flex items-center gap-1">
              <button
                onClick={toggleDockSide}
                className="p-1 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition flex items-center gap-1 text-[11px]"
                title={dockSide === 'left' ? "Dock Copilot to right" : "Dock Copilot to left"}
                aria-label={dockSide === 'left' ? "Dock Copilot to right" : "Dock Copilot to left"}
              >
                {dockSide === 'left' ? (
                  <>
                    <PanelRight className="h-3.5 w-3.5" />
                    <span className="hidden sm:inline text-[10px]">Right</span>
                  </>
                ) : (
                  <>
                    <PanelLeft className="h-3.5 w-3.5" />
                    <span className="hidden sm:inline text-[10px]">Left</span>
                  </>
                )}
              </button>

              <button
                onClick={() => setIsOpen(false)}
                className="p-1 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition"
                aria-label="Close Copilot"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
          </div>

          {/* Quick suggestions */}
          <div className="px-3 py-1.5 border-b border-slate-800/60 bg-slate-900/40 flex items-center gap-1.5 overflow-x-auto scrollbar-none text-xs">
            <span className="text-slate-500 flex items-center gap-1 shrink-0 text-[10px]">
              <Sparkles className="h-2.5 w-2.5 text-indigo-400" /> Prompts:
            </span>
            {samplePrompts.map((sp) => (
              <button
                key={sp.label}
                onClick={() => void handleSendMessage(sp.prompt)}
                disabled={isLoading}
                className="whitespace-nowrap px-2 py-0.5 rounded-full bg-slate-800/80 hover:bg-slate-700 border border-slate-700/60 text-slate-300 hover:text-white transition text-[10px] disabled:opacity-40"
              >
                {sp.label}
              </button>
            ))}
          </div>

          {/* Message List */}
          <div className="flex-1 overflow-y-auto p-3 space-y-3">
            {messages.map((msg) => (
              <div
                key={msg.id}
                className={`flex gap-2 ${msg.sender === 'user' ? 'justify-end' : 'justify-start'}`}
              >
                {msg.sender === 'agent' && (
                  <div className="h-6 w-6 rounded-md bg-indigo-600/20 border border-indigo-500/30 flex items-center justify-center text-indigo-400 shrink-0 mt-0.5">
                    <Bot className="h-3 w-3" />
                  </div>
                )}

                <div
                  className={`max-w-[88%] rounded-2xl p-2.5 sm:p-3 text-xs leading-relaxed ${
                    msg.sender === 'user'
                      ? 'bg-indigo-600 text-white rounded-br-none shadow-md shadow-indigo-600/10'
                      : 'bg-slate-900 border border-slate-800 text-slate-200 rounded-bl-none'
                  }`}
                >
                  {msg.agentName && (
                    <div className="flex items-center gap-1.5 mb-1 pb-1 border-b border-slate-800/80 text-[9px] font-mono text-indigo-400">
                      <span className="h-1.5 w-1.5 rounded-full bg-emerald-400"></span>
                      <span>{msg.agentName}</span>
                    </div>
                  )}

                  <div className="whitespace-pre-wrap">{msg.content}</div>

                  {msg.hitlPending && msg.hitlPayload && (
                    <HITLWidget payload={msg.hitlPayload} onResolved={handleHITLResolved} />
                  )}

                  <div className="mt-1 text-[9px] text-right opacity-50">
                    {msg.timestamp}
                  </div>
                </div>
              </div>
            ))}

            {isLoading && (
              <div className="flex gap-2 justify-start">
                <div className="h-6 w-6 rounded-md bg-indigo-600/20 border border-indigo-500/30 flex items-center justify-center text-indigo-400 shrink-0 animate-pulse">
                  <Bot className="h-3 w-3" />
                </div>
                <div className="bg-slate-900 border border-slate-800 rounded-xl rounded-bl-none p-2 text-xs text-slate-400 flex items-center gap-2">
                  <span className="h-1.5 w-1.5 rounded-full bg-indigo-500 animate-ping"></span>
                  <span className="text-[11px]">Thinking...</span>
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
            className="p-2.5 border-t border-slate-800/80 bg-slate-900/90 flex gap-1.5"
          >
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Ask about orders, products, policies..."
              disabled={isLoading}
              className="flex-1 bg-slate-950 border border-slate-800 focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 rounded-xl px-3 py-2 text-xs text-slate-100 placeholder-slate-500 outline-none transition"
            />
            <button
              type="submit"
              disabled={!input.trim() || isLoading}
              className="bg-indigo-600 hover:bg-indigo-500 text-white px-3 py-2 rounded-xl flex items-center justify-center transition disabled:opacity-40"
              aria-label="Send message"
            >
              <Send className="h-3.5 w-3.5" />
            </button>
          </form>
        </div>
      )}
    </>
  );
};
