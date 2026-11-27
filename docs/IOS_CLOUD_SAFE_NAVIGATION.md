# Native AList/OpenList directory path validation

The directory browser validates server-returned absolute paths before publishing a listing. It normalizes repeated separators, rejects malformed components, and leaves the prior listing visible when a response contains an invalid path. Child and parent navigation use the same path validation.
