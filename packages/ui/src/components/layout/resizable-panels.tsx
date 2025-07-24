import React, { useState, useRef, useEffect } from 'react';
import { cn } from '../../lib/utils';

interface ResizablePanelsProps {
  children: React.ReactNode[];
  orientation?: 'horizontal' | 'vertical';
  initialSizes?: number[];
  minSizes?: number[];
  className?: string;
}

export function ResizablePanels({
  children,
  orientation = 'horizontal',
  initialSizes,
  minSizes = [],
  className,
}: ResizablePanelsProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [sizes, setSizes] = useState<number[]>(
    initialSizes || new Array(children.length).fill(100 / children.length)
  );
  const [isResizing, setIsResizing] = useState(false);
  const [resizingIndex, setResizingIndex] = useState<number | null>(null);

  const startResize = (index: number) => (e: React.MouseEvent) => {
    e.preventDefault();
    setIsResizing(true);
    setResizingIndex(index);
  };

  useEffect(() => {
    if (!isResizing) return;

    const handleMouseMove = (e: MouseEvent) => {
      if (!containerRef.current || resizingIndex === null) return;

      const container = containerRef.current;
      const rect = container.getBoundingClientRect();
      
      const totalSize = orientation === 'horizontal' ? rect.width : rect.height;
      const position = orientation === 'horizontal' 
        ? ((e.clientX - rect.left) / totalSize) * 100
        : ((e.clientY - rect.top) / totalSize) * 100;

      const newSizes = [...sizes];
      const minSize1 = minSizes[resizingIndex] || 10;
      const minSize2 = minSizes[resizingIndex + 1] || 10;
      
      const currentTotal = newSizes[resizingIndex] + newSizes[resizingIndex + 1];
      const newSize1 = Math.max(minSize1, Math.min(position - sizes.slice(0, resizingIndex).reduce((a, b) => a + b, 0), currentTotal - minSize2));
      const newSize2 = currentTotal - newSize1;
      
      newSizes[resizingIndex] = newSize1;
      newSizes[resizingIndex + 1] = newSize2;
      
      setSizes(newSizes);
    };

    const handleMouseUp = () => {
      setIsResizing(false);
      setResizingIndex(null);
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);

    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isResizing, resizingIndex, sizes, orientation, minSizes]);

  return (
    <div
      ref={containerRef}
      className={cn(
        'flex h-full w-full',
        orientation === 'horizontal' ? 'flex-row' : 'flex-col',
        isResizing && 'select-none',
        className
      )}
    >
      {children.map((child, index) => (
        <React.Fragment key={index}>
          <div
            style={{
              [orientation === 'horizontal' ? 'width' : 'height']: `${sizes[index]}%`,
            }}
            className={cn(
              'overflow-hidden',
              orientation === 'horizontal' ? 'h-full' : 'w-full'
            )}
          >
            {child}
          </div>
          {index < children.length - 1 && (
            <div
              className={cn(
                'relative bg-border transition-colors hover:bg-primary/20',
                orientation === 'horizontal'
                  ? 'w-px cursor-col-resize'
                  : 'h-px cursor-row-resize',
                isResizing && resizingIndex === index && 'bg-primary'
              )}
              onMouseDown={startResize(index)}
            >
              <div
                className={cn(
                  'absolute',
                  orientation === 'horizontal'
                    ? 'inset-y-0 -left-1 -right-1'
                    : 'inset-x-0 -top-1 -bottom-1'
                )}
              />
            </div>
          )}
        </React.Fragment>
      ))}
    </div>
  );
}