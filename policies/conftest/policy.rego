package main

deny[msg] {
  input.kind == "Pod"
  some i
  endswith(input.spec.containers[i].image, ":latest")
  msg := sprintf("container %s uses latest tag", [input.spec.containers[i].name])
}

deny[msg] {
  input.kind == "Pod"
  some i
  input.spec.containers[i].securityContext.privileged == true
  msg := sprintf("container %s is privileged", [input.spec.containers[i].name])
}
