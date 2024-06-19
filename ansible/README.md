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
