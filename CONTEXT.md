# Pi Subagent Orchestration

This context describes delegated work performed by Pi children that are supervised through Herdr.

## Language

**Task**:
One delegated unit of work, from `subagent` launch until explicit completion, failure, or cancellation. An interactive Task can span multiple turns.
_Avoid_: Job

**Agent**:
The child Pi conversation performing a Task. An Agent becoming idle does not complete its Task.
_Avoid_: Task, worker process

**Turn**:
One prompt-and-response exchange with an Agent. Multiple turns may occur within one interactive Task.
_Avoid_: Task, session

**Result**:
The final Task payload returned to the parent when the Task completes.
_Avoid_: Notification, transcript
