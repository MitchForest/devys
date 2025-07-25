import React, { useState, useEffect } from 'react';
import { Button } from '../ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '../ui/card';
import { Progress } from '../ui/progress';
import { Badge } from '../ui/badge';
import { 
  Play, 
  X, 
  CheckCircle, 
  XCircle, 
  AlertCircle,
  Loader2,
  ChevronRight,
  Clock
} from 'lucide-react';
import { cn } from '../../lib/utils';
import type { 
  WorkflowExecution, 
  WorkflowProgressEvent,
  StepResult
} from '@devys/types';

interface WorkflowPanelProps {
  className?: string;
  activeChatSessionId?: string | null;
  ws?: WebSocket | null;
}

export function WorkflowPanel({ className, activeChatSessionId, ws }: WorkflowPanelProps) {
  const [selectedTemplate, setSelectedTemplate] = useState<string>('analyze-execute');
  const [execution, setExecution] = useState<WorkflowExecution | null>(null);
  const [progressEvents, setProgressEvents] = useState<WorkflowProgressEvent[]>([]);
  const [isStarting, setIsStarting] = useState(false);

  // Listen for WebSocket workflow progress events
  useEffect(() => {
    if (!ws) return;

    const handleMessage = (event: MessageEvent) => {
      try {
        const message = JSON.parse(event.data);
        
        if (message.type === 'workflow:progress') {
          const progressEvent = message.event as WorkflowProgressEvent;
          setProgressEvents(prev => [...prev, progressEvent]);
          
          // Update execution state based on progress
          if (progressEvent.type === 'started' || progressEvent.type === 'step-started') {
            fetchExecutionStatus(progressEvent.executionId);
          }
        }
      } catch (error) {
        console.error('Failed to parse WebSocket message:', error);
      }
    };

    ws.addEventListener('message', handleMessage);
    return () => ws.removeEventListener('message', handleMessage);
  }, [ws]);

  const fetchExecutionStatus = async (executionId: string) => {
    try {
      const response = await fetch(`http://localhost:3001/api/workflow/execution/${executionId}`);
      if (response.ok) {
        const data = await response.json();
        setExecution(data);
      }
    } catch (error) {
      console.error('Failed to fetch execution status:', error);
    }
  };

  const startWorkflow = async () => {
    if (!activeChatSessionId) {
      alert('Please start a chat session first');
      return;
    }

    setIsStarting(true);
    setProgressEvents([]);

    try {
      const response = await fetch('http://localhost:3001/api/workflow/start', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          template: selectedTemplate,
          sessionId: activeChatSessionId
        })
      });

      const data = await response.json();
      
      if (response.ok) {
        // Fetch initial execution state
        await fetchExecutionStatus(data.executionId);
      } else {
        console.error('Failed to start workflow:', data.error);
      }
    } catch (error) {
      console.error('Failed to start workflow:', error);
    } finally {
      setIsStarting(false);
    }
  };

  const cancelWorkflow = async () => {
    if (!execution) return;

    try {
      await fetch(`http://localhost:3001/api/workflow/execution/${execution.id}/cancel`, {
        method: 'POST'
      });
    } catch (error) {
      console.error('Failed to cancel workflow:', error);
    }
  };

  const getStepIcon = (step: StepResult) => {
    switch (step.status) {
      case 'completed':
        return <CheckCircle className="h-4 w-4 text-green-500" />;
      case 'failed':
        return <XCircle className="h-4 w-4 text-red-500" />;
      case 'running':
        return <Loader2 className="h-4 w-4 animate-spin text-blue-500" />;
      case 'skipped':
        return <AlertCircle className="h-4 w-4 text-gray-400" />;
      default:
        return <Clock className="h-4 w-4 text-gray-400" />;
    }
  };

  const getStatusBadge = (status: string) => {
    const variants: Record<string, string> = {
      'running': 'bg-blue-100 text-blue-800',
      'completed': 'bg-green-100 text-green-800',
      'failed': 'bg-red-100 text-red-800',
      'cancelled': 'bg-gray-100 text-gray-800'
    };

    return (
      <Badge className={cn('ml-2', variants[status] || 'bg-gray-100 text-gray-800')}>
        {status}
      </Badge>
    );
  };

  return (
    <div className={cn('flex flex-col h-full', className)}>
      <Card className="m-4">
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            Workflow Engine
            {execution && getStatusBadge(execution.status)}
          </CardTitle>
          <CardDescription>
            Run automated workflows to analyze and modify your codebase
          </CardDescription>
        </CardHeader>
        <CardContent>
          {!execution && (
            <div className="space-y-4">
              <div>
                <label className="text-sm font-medium">Select Workflow Template</label>
                <select 
                  className="w-full mt-1 p-2 border rounded-md"
                  value={selectedTemplate}
                  onChange={(e) => setSelectedTemplate(e.target.value)}
                >
                  <option value="analyze-execute">Analyze & Execute</option>
                </select>
              </div>
              
              <Button 
                onClick={startWorkflow} 
                disabled={isStarting || !activeChatSessionId}
                className="w-full"
              >
                {isStarting ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Starting Workflow...
                  </>
                ) : (
                  <>
                    <Play className="mr-2 h-4 w-4" />
                    Start Workflow
                  </>
                )}
              </Button>

              {!activeChatSessionId && (
                <p className="text-sm text-muted-foreground text-center">
                  Start a chat session to run workflows
                </p>
              )}
            </div>
          )}

          {execution && (
            <div className="space-y-4">
              {/* Progress Bar */}
              <div>
                <div className="flex justify-between text-sm mb-2">
                  <span>Progress</span>
                  <span>{Math.round(execution.progress)}%</span>
                </div>
                <Progress value={execution.progress} className="h-2" />
              </div>

              {/* Action Buttons */}
              {execution.status === 'running' && (
                <div className="flex gap-2">
                  <Button 
                    variant="outline" 
                    size="sm"
                    onClick={cancelWorkflow}
                    className="flex-1"
                  >
                    <X className="mr-2 h-4 w-4" />
                    Cancel
                  </Button>
                </div>
              )}

              {/* Steps */}
              <div className="space-y-2">
                <h4 className="text-sm font-medium">Steps</h4>
                {execution.results.map((result: StepResult) => (
                  <div 
                    key={result.stepId}
                    className={cn(
                      'flex items-center gap-2 p-2 rounded-md text-sm',
                      result.status === 'running' && 'bg-blue-50',
                      result.status === 'completed' && 'bg-green-50',
                      result.status === 'failed' && 'bg-red-50'
                    )}
                  >
                    {getStepIcon(result)}
                    <span className="flex-1">{result.stepId}</span>
                    {result.error && (
                      <span className="text-xs text-red-600">{result.error}</span>
                    )}
                  </div>
                ))}
              </div>

              {/* Recent Events */}
              {progressEvents.length > 0 && (
                <div className="space-y-2">
                  <h4 className="text-sm font-medium">Recent Activity</h4>
                  <div className="max-h-32 overflow-y-auto space-y-1">
                    {progressEvents.slice(-5).reverse().map((event, index) => (
                      <div key={index} className="text-xs text-muted-foreground">
                        <ChevronRight className="inline h-3 w-3" />
                        {event.message}
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Completion Actions */}
              {(execution.status === 'completed' || execution.status === 'failed') && (
                <Button 
                  variant="outline" 
                  size="sm"
                  onClick={() => {
                    setExecution(null);
                    setProgressEvents([]);
                  }}
                  className="w-full"
                >
                  Start New Workflow
                </Button>
              )}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}