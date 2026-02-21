package main

workload_kinds := {
  "Pod",
  "Deployment",
  "StatefulSet",
  "DaemonSet",
  "Job",
  "CronJob",
  "Rollout",
}

deny[msg] {
  workload_kinds[input.kind]
  c := workload_containers[_]
  image := c.image
  endswith(image, ":latest")
  msg := sprintf("%s/%s container image uses latest tag: %s", [input.kind, object.get(input.metadata, "name", "unknown"), image])
}

deny[msg] {
  workload_kinds[input.kind]
  c := workload_containers[_]
  image := c.image
  not contains(image, "@sha256:")
  msg := sprintf("%s/%s container image must use immutable digest: %s", [input.kind, object.get(input.metadata, "name", "unknown"), image])
}

workload_containers[c] {
  input.kind == "Pod"
  containers := object.get(input.spec, "containers", [])
  c := containers[_]
}

workload_containers[c] {
  input.kind == "Pod"
  init_containers := object.get(input.spec, "initContainers", [])
  c := init_containers[_]
}

workload_containers[c] {
  input.kind == "Deployment"
  template := object.get(input.spec, "template", {})
  pod_spec := object.get(template, "spec", {})
  containers := object.get(pod_spec, "containers", [])
  c := containers[_]
}

workload_containers[c] {
  input.kind == "Deployment"
  template := object.get(input.spec, "template", {})
  pod_spec := object.get(template, "spec", {})
  init_containers := object.get(pod_spec, "initContainers", [])
  c := init_containers[_]
}

workload_containers[c] {
  input.kind == "StatefulSet"
  template := object.get(input.spec, "template", {})
  pod_spec := object.get(template, "spec", {})
  containers := object.get(pod_spec, "containers", [])
  c := containers[_]
}

workload_containers[c] {
  input.kind == "StatefulSet"
  template := object.get(input.spec, "template", {})
  pod_spec := object.get(template, "spec", {})
  init_containers := object.get(pod_spec, "initContainers", [])
  c := init_containers[_]
}

workload_containers[c] {
  input.kind == "DaemonSet"
  template := object.get(input.spec, "template", {})
  pod_spec := object.get(template, "spec", {})
  containers := object.get(pod_spec, "containers", [])
  c := containers[_]
}

workload_containers[c] {
  input.kind == "DaemonSet"
  template := object.get(input.spec, "template", {})
  pod_spec := object.get(template, "spec", {})
  init_containers := object.get(pod_spec, "initContainers", [])
  c := init_containers[_]
}

workload_containers[c] {
  input.kind == "Job"
  template := object.get(input.spec, "template", {})
  pod_spec := object.get(template, "spec", {})
  containers := object.get(pod_spec, "containers", [])
  c := containers[_]
}

workload_containers[c] {
  input.kind == "Job"
  template := object.get(input.spec, "template", {})
  pod_spec := object.get(template, "spec", {})
  init_containers := object.get(pod_spec, "initContainers", [])
  c := init_containers[_]
}

workload_containers[c] {
  input.kind == "CronJob"
  job_template := object.get(input.spec, "jobTemplate", {})
  job_spec := object.get(job_template, "spec", {})
  template := object.get(job_spec, "template", {})
  pod_spec := object.get(template, "spec", {})
  containers := object.get(pod_spec, "containers", [])
  c := containers[_]
}

workload_containers[c] {
  input.kind == "CronJob"
  job_template := object.get(input.spec, "jobTemplate", {})
  job_spec := object.get(job_template, "spec", {})
  template := object.get(job_spec, "template", {})
  pod_spec := object.get(template, "spec", {})
  init_containers := object.get(pod_spec, "initContainers", [])
  c := init_containers[_]
}

workload_containers[c] {
  input.kind == "Rollout"
  template := object.get(input.spec, "template", {})
  pod_spec := object.get(template, "spec", {})
  containers := object.get(pod_spec, "containers", [])
  c := containers[_]
}

workload_containers[c] {
  input.kind == "Rollout"
  template := object.get(input.spec, "template", {})
  pod_spec := object.get(template, "spec", {})
  init_containers := object.get(pod_spec, "initContainers", [])
  c := init_containers[_]
}
