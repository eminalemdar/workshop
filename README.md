# workshop

Infrastructure behind the EKS workshop - a VPC, an EKS Auto Mode cluster, and the
ACK, kro and Argo CD capabilities running on top of it, plus the Argo CD bootstrap
that points the cluster at the app repository.

Spacelift applies all of it, so most of the time you won't be running `tofu` or
`kubectl` yourself. You'll edit a variable, push, and let the stack do the rest.

| | |
| --- | --- |
| Region | `eu-west-1` |
| Cluster | `workshop` |
| Space | `workshop` |

## Layout

| Path | What lives there |
| --- | --- |
| `aws/networking/` | VPC, subnets, NAT, routing |
| `aws/eks/` | The cluster and its capabilities |
| `kubernetes/` | Argo CD bootstrap manifests, applied with `kubectl` |
| `spacelift/` | The Spacelift space and the stack definitions |

## Step by step

Going from an empty account to a cluster you can run the exercises on is mostly
waiting - about five minutes of typing and twenty of watching runs.

### What you need first

- A Spacelift account with a VCS integration that can see your fork, and an AWS
  cloud integration whose role can create VPCs, EKS clusters, IAM roles and
  Identity Center groups.
- IAM Identity Center enabled in that AWS account in `eu-west-1`, with a user for
  yourself. Argo CD authenticates against it, and the `kubernetes` stack reads the
  instance during its plan - if there isn't one, the stack fails.
- `aws` and `kubectl` locally, plus a principal you can assume in the account.

### 1. Fork it and point it at your environment

Four variables still point at the environment this was built in. Find them with
`grep -rn "CHANGE ME" .` and set them as described in
[Configuration](#configuration).

Do `cluster_admin_principal_arns` now rather than later - it's what gets you
`kubectl` access, and setting it up front saves a second run through the cluster
stack.

If your fork isn't named `workshop`, set `repository_name` too.

### 2. Create the admin stack by hand

The stacks that do the work are defined in code, but something has to create them.
That one stack you make yourself, in the Spacelift UI:

| Setting | Value |
| --- | --- |
| Name | `workshop-admin` |
| Repository | your fork |
| Branch | `main` |
| Project root | `spacelift/` |
| Workflow tool | OpenTofu |

Then give the stack a role, which is the part that's easy to miss. Bind the
`Space admin` role to it in the `root` space - `spacelift/space.tf` creates the
`workshop` space underneath root, and that role only extends to creating spaces and
stacks when it's assigned there. Nothing narrower will do.

With the binding in place the `spacelift` provider authenticates as the run itself,
so there's no API key to create or store.

Trigger it. The run creates the `workshop` space and the `networking`, `kubernetes`
and `argocd` stacks inside it.

### 3. Apply networking

The stacks exist now but nothing has been pushed since they were created, so
trigger `networking` yourself this once. It builds the VPC, subnets, routing and a
single NAT gateway - a few minutes.

### 4. Apply kubernetes

`kubernetes` depends on `networking`, so it starts on its own once networking's run
finishes and receives the VPC and subnet IDs as inputs. If it hasn't picked them up
after a minute, trigger it.

This is the long one: control plane, Auto Mode, and the ACK, kro and Argo CD
capabilities. Budget fifteen to twenty minutes.

### 5. Apply the Argo CD manifests

`argocd` depends on `kubernetes` the same way, so it also starts on its own once
that run finishes, and receives the cluster name as an input. It's a Kubernetes
stack rather than an OpenTofu one: the plan is `kubectl apply --dry-run` and the
deploy the same apply for real, over everything in `kubernetes/`. Seconds, not
minutes.

That registers the cluster and the app repository with Argo CD and creates the two
app-of-apps Applications, which then sync the kro manifests out of the
[2048](https://github.com/eminalemdar/2048) repo on their own.

### 6. Get a kubeconfig

Your access entry was created by step 4, so this should just work:

```bash
aws eks update-kubeconfig --region eu-west-1 --name workshop
kubectl get ns
```

An `Unauthorized` here means your principal isn't in
`cluster_admin_principal_arns` - see [Getting access to the
cluster](#getting-access-to-the-cluster).

### 7. Confirm the capabilities came up

```bash
kubectl get capability
kubectl api-resources | grep -E 's3.services.k8s.aws|kro.run'
```

Three capabilities, and CRDs from both ACK and kro. If the CRDs aren't there yet,
give the capability another minute and look again.

Then the Argo CD side:

```bash
kubectl get applications -n argocd
```

`kro-rgd` and `kro-instances`, both `Synced` and `Healthy`. `kro-instances` can sit
`OutOfSync` for a round or two on a first sync, then retries into place.

### Tearing it down

Destroy in the reverse order you built: `argocd` first, then task or destroy
`kubernetes`, then `networking`, then delete `workshop-admin`. Going the other way
leaves the VPC pinned by the cluster's ENIs.

Delete any ACK or kro objects you created before destroying the cluster. Their AWS
resources are owned by controllers running outside it, so tearing down the cluster
first orphans the buckets rather than removing them. The kro instances Argo CD
syncs count here too - destroying `argocd` while the cluster is still up deletes
the Applications, and their finalizers are what let Argo CD prune what they
created.

## Configuration

If you're forking this, four variables still point at the environment it was built
in and won't work anywhere else. They're marked in the code, so you can find them
with:

```bash
grep -rn "CHANGE ME" .
```

| Variable | Where | What it is |
| --- | --- | --- |
| `aws_integration_id` | `spacelift/variables.tf` | The Spacelift AWS integration the stacks assume |
| `vcs` | `spacelift/variables.tf` | Your VCS namespace and integration |
| `cluster_admin_principal_arns` | `aws/eks/variables.tf` | IAM principals that get cluster admin |
| `argocd_admin_user_names` | `aws/eks/variables.tf` | Identity Center users that get Argo CD ADMIN |

Edit the defaults directly, or leave them alone and override per stack in Spacelift
with `TF_VAR_<name>`. If you go the environment variable route, the list and object
values need to parse as HCL - brackets and braces included:

```bash
TF_VAR_cluster_admin_principal_arns='["arn:aws:iam::<account-id>:user/<you>"]'
TF_VAR_vcs='{type="GITHUB",enterprise=true,namespace="<your-org>",id="<vcs-integration-id>"}'
```

Everything else - region, cluster name, CIDR, Kubernetes and kubectl versions -
has a sensible default in the `variables.tf` next to each stack.

One pair has to agree, either side of the OpenTofu/kubectl line: `argocd_namespace`
in `aws/eks/variables.tf` installs Argo CD, and `argocd_namespace` in
`spacelift/variables.tf` is where the `argocd` stack applies its manifests.

## How changes get applied

There are three stacks in the `workshop` space:

| Stack | Tracks | Tool |
| --- | --- | --- |
| `networking` | `aws/networking` | OpenTofu |
| `kubernetes` | `aws/eks` | OpenTofu |
| `argocd` | `kubernetes/` | kubectl |

`kubernetes` depends on `networking` and pulls the VPC and subnet IDs out of its
outputs. `argocd` depends on `kubernetes` the same way, taking the cluster name and
region from its `cluster_name` and `region` outputs.

Those two are the whole of the stack's authentication. A `before_init` hook runs
`aws eks update-kubeconfig` with them, turning the AWS integration's credentials
into a kubeconfig - and since that role created the cluster, it's already a cluster
admin, so there's no access entry to add for it.

All three track `main` with auto-deploy on. Push and the affected stack plans and
applies on its own - there's no confirmation step waiting for you. If you'd rather
see the plan first, open a pull request instead; that gives you a proposed run and
leaves the tracked stack alone.

Changes under `spacelift/` are applied by the `workshop-admin` stack, so adding a
new stack works the same way as everything else.

## Getting access to the cluster

Your IAM principal needs an access entry before `kubectl` will work. Add it to
`cluster_admin_principal_arns` in `aws/eks/variables.tf` and push, then run the
commands from [step 6](#6-get-a-kubeconfig) again. The cluster is API-auth only, so
there's no `aws-auth` ConfigMap to go hunting for.

If `kubectl get nodes` comes back empty, nothing is wrong. Auto Mode scales from
zero and will bring up a node as soon as something needs to be scheduled.

## Argo CD

You can reach the UI from the Capabilities tab of the cluster in the EKS console,
or grab the URL directly:

```bash
kubectl get capability argocd -o jsonpath='{.status.serverUrl}'
```

Sign in with IAM Identity Center. There's no local admin account and no
`argocd-rbac-cm` to edit — who gets in is decided entirely by the capability's
role mapping.

To give someone the ADMIN role, add their Identity Center user name here:

```hcl
# aws/eks/variables.tf
argocd_admin_user_names = ["your-idc-user", "a-colleague"]
```

They need to already exist as a user in the Identity Center directory, since this
repo doesn't create people. Pushing adds them to the `argocd-admins` group, which
is what ADMIN is mapped to. The Identity Center application assignment sorts
itself out, so leave that alone.

### What's bootstrapped

`kubernetes/` holds the manifests the `argocd` stack applies:

| File | What it does |
| --- | --- |
| `cluster-local.yaml` | Registers the cluster, by ARN, as the `in-cluster` target |
| `repository-2048.yaml` | Registers `https://github.com/eminalemdar/2048` as a source |
| `app-of-apps-kro-rgd.yaml` | Syncs `kubernetes/kro` from that repo - the ResourceGraphDefinitions |
| `app-of-apps-kro-instances.yaml` | Syncs `kubernetes/kro/instances` - the resources built from them |

They're two Applications rather than one recursive sync because of the two-step
thing described under [kro](#kro): the instances need APIs that only exist once the
RGDs are reconciled. Nothing orders them, so `kro-instances` retries until they're
there. Both have `prune` and `selfHeal` on, so from then on the cluster follows the
2048 repo.

None of the files carry a `metadata.namespace` - the stack supplies it with
`kubectl -n`, so applying one by hand needs `-n argocd`. Adding more to Argo CD
means dropping another manifest into `kubernetes/` and pushing.

Two things about this capability differ from self-managed Argo CD, and both bite
immediately if you miss them:

- Clusters are identified by **EKS cluster ARN**, not API server URL.
  `https://kubernetes.default.svc` is rejected outright, and the local cluster is
  not registered for you. The manifests carry a `__CLUSTER_ARN__` placeholder that
  a `before_init` hook fills in from the cluster stack's `cluster_arn` output, so
  there's nothing account-specific to edit.
- The capability role gets an access entry but **no Kubernetes RBAC**, so Argo CD
  authenticates and then fails every deploy. `aws/eks/main.tf` associates
  `AmazonEKSClusterAdminPolicy` with it, same as it does for kro.

## ACK

The controllers run on AWS-managed infrastructure - there's nothing to install and
you won't see any pods for it in the cluster. The CRDs are already registered, so
you can go straight to creating AWS resources through Kubernetes:

```yaml
apiVersion: s3.services.k8s.aws/v1alpha1
kind: Bucket
metadata:
  name: demo
  namespace: default
spec:
  name: workshop-demo-<your-suffix>
```

Bucket names are globally unique, so pick something specific to you. Then watch it
settle:

```bash
kubectl describe bucket demo
```

- Deleting the Kubernetes object deletes the real AWS resource. If that's not what
  you want, add the `services.k8s.aws/deletion-policy: retain` annotation.
- To adopt something that already exists rather than create it fresh, use
  `services.k8s.aws/adoption-policy: adopt-or-create`.

## kro

kro lets you bundle several resources behind a single custom API. It's a two-step
thing, which is the part that usually trips people up the first time.

### 1. Define the API

Applying a ResourceGraphDefinition doesn't create anything in AWS. It defines a new
type and registers it with the cluster:

```yaml
apiVersion: kro.run/v1alpha1
kind: ResourceGraphDefinition
metadata:
  name: simple-bucket
spec:
  schema:
    apiVersion: v1alpha1
    kind: SimpleBucket
    spec:
      name: string
  resources:
    - id: bucket
      template:
        apiVersion: s3.services.k8s.aws/v1alpha1
        kind: Bucket
        metadata:
          name: ${schema.spec.name}
        spec:
          name: ${schema.spec.name}
```

Check it registered before going further:

```bash
kubectl get rgd
kubectl api-resources | grep SimpleBucket
```

### 2. Create an instance

This is the step that actually builds something:

```yaml
apiVersion: kro.run/v1alpha1
kind: SimpleBucket
metadata:
  name: my-bucket
  namespace: default
spec:
  name: workshop-kro-<your-suffix>
```

Now the underlying `Bucket` appears, and the S3 bucket behind it. Delete the
`SimpleBucket` and everything it created goes with it.

The example is deliberately tiny. What makes kro interesting is that a graph can
hold several resources at once, working out the ordering and passing values between
them - a bucket plus a queue plus the notification wiring, from one custom
resource.

If an instance gets accepted but nothing shows up underneath it, that's usually kro
lacking permission for the kinds in the graph. `kro_access_policy_arn` in
`aws/eks/variables.tf` is the knob for that.
