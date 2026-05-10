/**
 * Modal for creating the first student.
 * Auto-opens when user has no students, with a friendly welcome message.
 */
import { useState } from "react"
import {
  ScribbleButton,
  ScribbleDialog,
  ScribbleDialogContent,
  ScribbleDialogDescription,
  ScribbleDialogFooter,
  ScribbleDialogHeader,
  ScribbleDialogTitle,
  ScribbleInput,
  ScribbleLabel,
  toast,
} from "@/components/scribble-ui"
import { useCreateStudent } from "@/hooks/use-students"
import { getUserFacingErrorMessage } from "@/lib/user-facing-error"

interface CreateStudentModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onSuccess?: () => void
}

export function CreateStudentModal({
  open,
  onOpenChange,
  onSuccess,
}: CreateStudentModalProps) {
  const [name, setName] = useState("")
  const createStudent = useCreateStudent()

  const isValid = name.trim().length >= 1

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()

    if (!isValid) return

    try {
      await createStudent.mutateAsync({
        displayName: name.trim(),
      })
      toast.success("Student created")
      onSuccess?.()
    } catch (error) {
      toast.error(getUserFacingErrorMessage(error))
    }
  }

  return (
    <ScribbleDialog open={open} onOpenChange={onOpenChange}>
      <ScribbleDialogContent>
        <ScribbleDialogHeader>
          <ScribbleDialogTitle>Create your first student</ScribbleDialogTitle>
          <ScribbleDialogDescription>
            This will show up in your classroom list.
          </ScribbleDialogDescription>
        </ScribbleDialogHeader>
        <form onSubmit={handleSubmit}>
          <ScribbleLabel htmlFor="student-name">Name</ScribbleLabel>
          <ScribbleInput
            id="student-name"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
          <ScribbleDialogFooter>
            <ScribbleButton type="submit" disabled={!isValid}>
              Create student
            </ScribbleButton>
          </ScribbleDialogFooter>
        </form>
      </ScribbleDialogContent>
    </ScribbleDialog>
  )
}
