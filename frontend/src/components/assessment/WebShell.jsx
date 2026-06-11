import { useState, useEffect, useRef, useCallback } from 'react';
import commandService from '../../services/commandService';

const stripAnsi = (str) => str.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, '');

export default function WebShell({ assessmentId, assessmentName }) {
  const [entries, setEntries] = useState([]);
  const [input, setInput] = useState('');
  const [cmdHistory, setCmdHistory] = useState([]);
  const [historyIdx, setHistoryIdx] = useState(-1);
  const [isRunning, setIsRunning] = useState(false);

  const bodyRef = useRef(null);
  const inputRef = useRef(null);

  useEffect(() => {
    if (bodyRef.current) {
      bodyRef.current.scrollTop = bodyRef.current.scrollHeight;
    }
  }, [entries]);

  const focusInput = useCallback(() => {
    inputRef.current?.focus();
  }, []);

  const handleClear = useCallback(() => {
    setEntries([]);
    focusInput();
  }, [focusInput]);

  const runCommand = useCallback(async (cmd) => {
    const trimmed = cmd.trim();
    if (!trimmed) return;

    if (trimmed === 'clear') {
      setEntries([]);
      setInput('');
      setCmdHistory((h) => [trimmed, ...h]);
      setHistoryIdx(-1);
      return;
    }

    setEntries((prev) => [...prev, { type: 'input', content: trimmed }]);
    setInput('');
    setCmdHistory((h) => [trimmed, ...h]);
    setHistoryIdx(-1);
    setIsRunning(true);

    try {
      const result = await commandService.execute(assessmentId, trimmed);
      const stdout = stripAnsi(result.stdout || '');
      const stderr = stripAnsi(result.stderr || '');

      setEntries((prev) => [
        ...prev,
        ...(stdout ? [{ type: 'output', content: stdout }] : []),
        ...(stderr ? [{ type: 'error', content: stderr }] : []),
        {
          type: 'meta',
          exitCode: result.returncode ?? (result.success ? 0 : 1),
          time: result.execution_time,
        },
      ]);
    } catch (err) {
      const msg = err?.response?.data?.detail || err.message || 'Execution failed';
      setEntries((prev) => [...prev, { type: 'error', content: msg }]);
    } finally {
      setIsRunning(false);
    }
  }, [assessmentId]);

  const handleKeyDown = useCallback((e) => {
    if (e.key === 'Enter' && !isRunning) {
      runCommand(input);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setHistoryIdx((idx) => {
        const next = Math.min(idx + 1, cmdHistory.length - 1);
        setInput(cmdHistory[next] ?? '');
        return next;
      });
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      setHistoryIdx((idx) => {
        const next = Math.max(idx - 1, -1);
        setInput(next === -1 ? '' : (cmdHistory[next] ?? ''));
        return next;
      });
    } else if (e.key === 'l' && e.ctrlKey) {
      e.preventDefault();
      handleClear();
    }
  }, [isRunning, input, cmdHistory, runCommand, handleClear]);

  const prompt = assessmentName
    ? `aso@${assessmentName.toLowerCase().replace(/\s+/g, '-')}:~$`
    : 'aso:~$';

  return (
    <div className="flex flex-col" onClick={focusInput}>
      {/* Header */}
      <div className="px-4 py-3 border-b border-neutral-200 dark:border-neutral-700 bg-gray-50 dark:bg-neutral-900 rounded-t-lg flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="flex gap-1.5">
            <div className="w-3 h-3 rounded-full bg-red-500/70" />
            <div className="w-3 h-3 rounded-full bg-yellow-500/70" />
            <div className="w-3 h-3 rounded-full bg-green-500/70" />
          </div>
          <h2 className="text-sm font-semibold text-gray-800 dark:text-neutral-100 ml-2">Shell</h2>
          <span className="text-xs text-gray-400 dark:text-neutral-500 font-mono">{assessmentName}</span>
        </div>
        <button
          onClick={(e) => { e.stopPropagation(); handleClear(); }}
          className="text-xs text-neutral-400 hover:text-neutral-600 dark:hover:text-neutral-200 transition-colors"
        >
          clear
        </button>
      </div>

      {/* Terminal body */}
      <div
        ref={bodyRef}
        className="bg-neutral-950 rounded-b-lg p-4 font-mono text-xs min-h-64 max-h-96 overflow-y-auto cursor-text"
      >
        {entries.length === 0 && (
          <p className="text-neutral-600 select-none">
            # Type a command and press Enter. Use ↑↓ to recall history, Ctrl+L to clear.
          </p>
        )}

        {entries.map((entry, i) => {
          if (entry.type === 'input') {
            return (
              <div key={i} className="flex gap-2 mt-1 first:mt-0">
                <span className="text-neutral-500 shrink-0">{prompt}</span>
                <span className="text-green-300 break-all">{entry.content}</span>
              </div>
            );
          }
          if (entry.type === 'output') {
            return (
              <pre key={i} className="text-green-400 whitespace-pre-wrap break-all leading-relaxed">
                {entry.content}
              </pre>
            );
          }
          if (entry.type === 'error') {
            return (
              <pre key={i} className="text-red-400 whitespace-pre-wrap break-all leading-relaxed">
                {entry.content}
              </pre>
            );
          }
          if (entry.type === 'meta') {
            const ok = entry.exitCode === 0;
            return (
              <div key={i} className="flex items-center gap-2 mt-0.5 mb-1 text-neutral-600">
                <span className={ok ? 'text-green-600' : 'text-red-500'}>
                  {ok ? '✓' : '✗'} {entry.exitCode}
                </span>
                {entry.time != null && (
                  <span>{entry.time.toFixed(2)}s</span>
                )}
              </div>
            );
          }
          return null;
        })}

        {/* Running indicator */}
        {isRunning && (
          <div className="flex items-center gap-1 text-yellow-500 mt-1 animate-pulse">
            <span>running</span>
            <span className="animate-bounce">▌</span>
          </div>
        )}

        {/* Active input line */}
        {!isRunning && (
          <div className="flex gap-2 mt-1 items-center">
            <span className="text-neutral-500 shrink-0">{prompt}</span>
            <input
              ref={inputRef}
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              disabled={isRunning}
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="off"
              spellCheck={false}
              className="flex-1 bg-transparent outline-none text-green-300 caret-green-400 min-w-0"
            />
          </div>
        )}
      </div>
    </div>
  );
}
