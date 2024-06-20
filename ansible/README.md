# Ansible

Use the pipenv env:

```bash
pipenv shell
```

Install the roles:

```bash
ansible-galaxy role install -r requirements.yaml
```

Run the playbook

```bash
ansible-playbook -i inventory.ini playbook.yaml
```

## New hosts

New hosts need their zerotier identity keys updated from the terraform output.

```bash
export target_host=test.dzerv.art
terraform output -json zerotier_identities | jq -r ".\"$target_host\".private" | ssh $target_host "sudo tee /var/lib/zerotier-one/identity.secret"
terraform output -json zerotier_identities | jq -r ".\"$target_host\".public" | ssh $target_host "sudo tee /var/lib/zerotier-one/identity.public"
```
