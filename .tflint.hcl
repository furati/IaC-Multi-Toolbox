config {
  # Lint modules and surface all issues (do not stop at the first error).
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
