import React from 'react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '../ui/dialog';
import { Button } from '../ui/button';
import { ScrollArea } from '../ui/scroll-area';
import { AlertTriangle, FileEdit, Terminal, Trash2 } from 'lucide-react';
import type { WorkflowApprovalRequest, PlannedAction } from '@devys/types';

interface WorkflowApprovalDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  approvalRequest: WorkflowApprovalRequest | null;
  onApprove: () => void;
  onReject: () => void;
}

export function WorkflowApprovalDialog({
  open,
  onOpenChange,
  approvalRequest,
  onApprove,
  onReject
}: WorkflowApprovalDialogProps) {
  if (!approvalRequest) return null;

  const getActionIcon = (action: PlannedAction) => {
    switch (action.type) {
      case 'file-write':
        return <FileEdit className="h-4 w-4" />;
      case 'file-delete':
        return <Trash2 className="h-4 w-4 text-red-600" />;
      case 'command-run':
        return <Terminal className="h-4 w-4" />;
      case 'tool-invoke':
        return <AlertTriangle className="h-4 w-4 text-blue-600" />;
      default:
        return <AlertTriangle className="h-4 w-4" />;
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Workflow Approval Required</DialogTitle>
          <DialogDescription>
            The workflow step &quot;{approvalRequest.stepId}&quot; requires your approval to proceed.
          </DialogDescription>
        </DialogHeader>

        <div className="my-4">
          <h4 className="text-sm font-medium mb-2">Description</h4>
          <p className="text-sm text-muted-foreground">{approvalRequest.description}</p>
        </div>

        {approvalRequest.plannedActions.length > 0 && (
          <div className="my-4">
            <h4 className="text-sm font-medium mb-2">Planned Actions</h4>
            <ScrollArea className="h-64 w-full rounded-md border p-4">
              <div className="space-y-3">
                {approvalRequest.plannedActions.map((action: any, index: number) => (
                  <div key={index} className="flex items-start gap-3">
                    {getActionIcon(action)}
                    <div className="flex-1">
                      <p className="text-sm font-medium">{action.description}</p>
                      {action.details && (
                        <pre className="mt-1 text-xs text-muted-foreground bg-muted p-2 rounded">
                          {JSON.stringify(action.details, null, 2)}
                        </pre>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            </ScrollArea>
          </div>
        )}

        <DialogFooter>
          <Button variant="outline" onClick={onReject}>
            Reject
          </Button>
          <Button onClick={onApprove}>
            Approve & Continue
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}