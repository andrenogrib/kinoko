## Kinoko v95 - Guia Local Windows (resumo completo do que fizemos)

Este repositorio e um servidor de MapleStory v95 (Kinoko).

Este README foi atualizado com o fluxo real usado no Windows para subir servidor local sem dor de cabeca.

## Repositorios usados

- Server: este repositorio (`kinoko`)
- Client v95: `https://github.com/iw2d/kinoko_client`

## Ambiente usado hoje

- Windows + PowerShell
- Docker Desktop (Engine running)
- Java 21
- Maven (instalado no sistema ou configurado no VSCode)
- Git
- IDE: VSCode (Java e Maven configurados) + terminal PowerShell no Windows

## Estrutura de pastas recomendada

Na raiz do projeto:

- `data/` (ja vem no repo)
- `wz/` (voce cria)
- `logs/` (criada automaticamente pelo script de start)
- `client_bin/` (opcional para manter arquivos de client no workspace)

Obs: `wz/`, `logs/` e `client_bin/` estao no `.gitignore`.

## WZ (obrigatorio)

Voce precisa instalar MapleStory v95 primeiro.

Depois, crie a pasta `wz` na raiz do servidor e copie para ela os WZ originais da pasta do MapleStory v95 (instalacao oficial do client).

Arquivos esperados:

```text
Character.wz
Item.wz
Skill.wz
Morph.wz
Map.wz
Mob.wz
Npc.wz
Reactor.wz
Quest.wz
String.wz
Etc.wz
```

Sem isso o server nao sobe corretamente porque os providers carregam dados direto desses WZ.

## Client (v95)

Repositorio do client:

`https://github.com/iw2d/kinoko_client`

Fluxo pratico:

1. Instalar MapleStory v95 no Windows.
2. Colocar o `kinoko_client` dentro da pasta do MapleStory v95.
3. Copiar os WZ originais dessa mesma pasta do MapleStory v95 para a pasta `wz/` do servidor.
4. Seguir o README do client para configuracoes especificas dele.
5. Subir o server local e conectar no `127.0.0.1`.

## Start/Stop/Status no Windows

Criamos 3 scripts PowerShell para facilitar:

- `start-local.ps1`
- `status-local.ps1`
- `stop-local.ps1`

### Start

```powershell
powershell -ExecutionPolicy Bypass -File .\start-local.ps1
```

Sem rebuild:

```powershell
powershell -ExecutionPolicy Bypass -File .\start-local.ps1 -SkipBuild
```

O script faz:

1. Resolve `docker`, `java` e `mvn`.
2. Build do jar (`mvn clean package -Dmaven.test.skip=true`) se nao usar `-SkipBuild`.
3. Sobe Cassandra container `kinoko-db` na porta `9042`.
4. Espera o Cassandra ficar pronto com `cqlsh`.
5. Sobe `java -jar target/server.jar`.
6. Aguarda porta de login `8484`.

### Status

```powershell
powershell -ExecutionPolicy Bypass -File .\status-local.ps1
```

Mostra:

- container do banco
- processo java do server
- portas `8484`, `8585`, `8282`, `9042`

### Stop

```powershell
powershell -ExecutionPolicy Bypass -File .\stop-local.ps1
```

Para:

- processo do server
- container `kinoko-db`

## Comandos manuais (sem script)

### Banco

```powershell
docker run -d --name kinoko-db -p 9042:9042 cassandra:5.0.0-jammy
```

### Build

```powershell
mvn clean package -Dmaven.test.skip=true
```

### Rodar server

```powershell
$env:DATABASE_HOST="127.0.0.1"
$env:SERVER_HOST="127.0.0.1"
$env:CENTRAL_HOST="127.0.0.1"
java -jar target/server.jar
```

## Variaveis importantes do servidor

As configs principais ficam em:

- [ServerConstants.java](src/main/java/kinoko/server/ServerConstants.java)
- [ServerConfig.java](src/main/java/kinoko/server/ServerConfig.java)

Pontos usados no local:

- `DATABASE_HOST` (padrao `127.0.0.1`)
- `WORLD_NAME` (padrao `Kinoko`)
- `WZ_DIRECTORY` (padrao `wz`)
- `DATA_DIRECTORY` (padrao `data`)
- `COMMAND_PREFIX` (padrao `!`)
- `AUTO_CREATE_ACCOUNT` (padrao `true`)

## Conta e login (importante)

- Se `AUTO_CREATE_ACCOUNT=true`, ao tentar logar com usuario inexistente o server cria a conta automaticamente.
- Na primeira tentativa pode voltar como nao registrado; tente logar de novo.
- Senha e salva com BCrypt (hash), nao em texto puro.

## Banco de dados (Cassandra)

Este projeto usa Cassandra por padrao.

- Host/porta: `127.0.0.1:9042` (ou `DATABASE_HOST`)
- Keyspace: `kinoko`
- Tabelas principais: `account_table`, `character_table`, `id_table`

### Acessar via terminal

```powershell
docker exec -it kinoko-db cqlsh
```

Se `docker` nao estiver no PATH:

```powershell
& "C:\Program Files\Docker\Docker\resources\bin\docker.exe" exec -it kinoko-db cqlsh
```

### CQL util

```sql
DESCRIBE KEYSPACES;
USE kinoko;
DESCRIBE TABLES;

SELECT account_id, username FROM account_table LIMIT 20;
SELECT character_id, account_id, character_name, money FROM character_table LIMIT 20;

UPDATE account_table SET nx_credit = 100000 WHERE account_id = 1;
UPDATE character_table SET money = 50000000 WHERE character_id = 1;
```

## Comandos de admin in-game

Prefixo padrao: `!`

Exemplos:

- `!help`
- `!map <fieldId>`
- `!item <itemId> [qtd]`
- `!reloaddrops`
- `!reloadshops`
- `!npc <npcId>` (abre script do NPC, nao shop direto)

Obs: hoje nao existe checagem forte de permissao de comando no processor. Use em ambiente local/dev.

## GM Shop

As shops ficam em `data/shop/<npcId>.yaml`.

Formato:

```yaml
recharge: true
items:
  - [ 2000000, 50 ]
  - [ 2000001, 160, 1, 100 ]
```

Depois de editar:

```text
!reloadshops
```

Para abrir loja, normalmente voce clica num NPC que tenha shop no map.

## Onde ficam os calculos de EXP / DROP / QUEST hoje

- EXP de mob: `src/main/java/kinoko/world/field/mob/Mob.java`
- Drop de mob: `src/main/java/kinoko/world/field/mob/Mob.java`
- Reward YAML por mob: `data/reward/*.yaml`
- Quest EXP act: `src/main/java/kinoko/provider/quest/act/QuestExpAct.java`
- Quest meso act: `src/main/java/kinoko/provider/quest/act/QuestMoneyAct.java`
- Script rewards (eventos/quests scriptadas): `src/main/java/kinoko/script/common/ScriptManagerImpl.java`

## Troubleshooting rapido

### "docker nao reconhecido"

1. Feche e abra terminal/IDE apos instalar Docker Desktop.
2. Teste `docker --version`.
3. Se necessario, use caminho completo do docker exe.

### Client mostra server off

Checklist:

1. `status-local.ps1` mostra porta `8484` em LISTEN?
2. Cassandra em `9042` esta de pe?
3. Server host local esta `127.0.0.1`?
4. Verifique logs em `logs/server.out.log` e `logs/server.err.log`.
5. Verifique configuracao do client local (IP/version) no repo do client.

## Resumo do dia

- Migramos tentativa de v83 para v95.
- Subimos stack local no Windows com Docker + Cassandra + Java 21 + Maven.
- Criamos scripts de operacao local (`start-local.ps1`, `status-local.ps1`, `stop-local.ps1`).
- Validamos estrutura de WZ na pasta `wz/`.
- Confirmamos fluxo de shop/drop/quest/admin command no codigo.
