#!/usr/bin/env bash
# =============================================================================
# CRUD na nuvem — curls prontos para copiar e colar (Tutor + Pet)
# Time CCGL · RM564113
# =============================================================================
# Depois do login, substitua COLE_O_JWT_AQUI pelo token (eyJ...) em todos
# os POST/PUT/DELETE. IDs 1 e 2 assumem o primeiro tutor/pet criados nesta
# sessão — ajuste o número no URL/JSON se o POST devolver outro "id".
# =============================================================================

UNIQ="$(date +%s)"
CPF1="1$(printf '%010d' $((UNIQ % 10000000000)))"
CPF2="2$(printf '%010d' $((UNIQ % 10000000000)))"

cat <<EOF
# GET tutores (público)
curl -s https://app-ccgl-rm564113.azurewebsites.net/veti/tutores

# Registrar ADMIN (200 = novo · 400 = e-mail já existe)
curl -s -X POST https://app-ccgl-rm564113.azurewebsites.net/veti/auth/register -H "Content-Type: application/json" -d '{"email":"vet@ccgl.com","password":"SenhaForte!123","role":"ADMIN"}'

# Login — copie o JWT da resposta (texto eyJ..., sem aspas)
curl -s -X POST https://app-ccgl-rm564113.azurewebsites.net/veti/auth/login -H "Content-Type: application/json" -d '{"email":"vet@ccgl.com","password":"SenhaForte!123"}'

# Criar tutor 1
curl -s -X POST https://app-ccgl-rm564113.azurewebsites.net/veti/tutores -H "Authorization: Bearer COLE_O_JWT_AQUI" -H "Content-Type: application/json" -d '{"name":"Ana Silva","email":"ana${UNIQ}@ccgl.com","phone":"11999999999","cpf":"${CPF1}"}'

# Criar tutor 2
curl -s -X POST https://app-ccgl-rm564113.azurewebsites.net/veti/tutores -H "Authorization: Bearer COLE_O_JWT_AQUI" -H "Content-Type: application/json" -d '{"name":"Bruno Souza","email":"bruno${UNIQ}@ccgl.com","phone":"11888888888","cpf":"${CPF2}"}'

# Criar pet 1 (idTutor = id do tutor 1)
curl -s -X POST https://app-ccgl-rm564113.azurewebsites.net/veti/pets -H "Authorization: Bearer COLE_O_JWT_AQUI" -H "Content-Type: application/json" -d '{"name":"Rex","raca":"LABRADOR_RETRIEVER","peso":28.5,"idade":4,"castrado":true,"idTutor":1}'

# Criar pet 2 (idTutor = id do tutor 2)
curl -s -X POST https://app-ccgl-rm564113.azurewebsites.net/veti/pets -H "Authorization: Bearer COLE_O_JWT_AQUI" -H "Content-Type: application/json" -d '{"name":"Mimi","raca":"PERSIAN","peso":4.2,"idade":2,"castrado":false,"idTutor":2}'

# Consultar
curl -s https://app-ccgl-rm564113.azurewebsites.net/veti/tutores?size=10
curl -s https://app-ccgl-rm564113.azurewebsites.net/veti/pets?size=10

# Alterar tutor 1
curl -s -X PUT https://app-ccgl-rm564113.azurewebsites.net/veti/tutores/1 -H "Authorization: Bearer COLE_O_JWT_AQUI" -H "Content-Type: application/json" -d '{"name":"Ana Silva Costa","email":"ana${UNIQ}@ccgl.com","phone":"11777777777","cpf":"${CPF1}"}'

# Excluir pet 2
curl -s -X DELETE https://app-ccgl-rm564113.azurewebsites.net/veti/pets/2 -H "Authorization: Bearer COLE_O_JWT_AQUI"

# Persistência (PostgreSQL) — troque a senha
az postgres flexible-server execute --name pg-ccgl-rm564113 --admin-user ccgl --admin-password 'SuaSenhaForte!123' --database-name db-challenge --querytext 'SELECT * FROM "TB_TUTOR" LIMIT 10; SELECT * FROM "TB_PET" LIMIT 10;'
EOF
