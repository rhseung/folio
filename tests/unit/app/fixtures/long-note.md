# 매칭과 덮개

이 노트는 화면보다 길어서 열면 아래로 이어진다. 노트 보기 검사가 여는 직후와 스크롤한 뒤의 화면, 클릭, 노트 끝 아래의 여백을 본다. Task box와 접힌 콜아웃, 링크는 넣지 않는다. 격자 클릭이 노트를 바꾸지 않게 하기 위해서다.

그래프 $G$의 매칭(matching)은 서로 끝점을 공유하지 않는 간선의 집합이다. 최대 매칭은 더 큰 매칭이 없는 매칭이고, 완전 매칭은 모든 정점을 덮는 매칭이다.
한 줄 안에서 줄바꿈된 문장은 같은 문단에 남는다.

## 증가 경로

매칭 $M$에 대해 $M$-교대 경로는 $M$에 속한 간선과 속하지 않은 간선을 번갈아 지나는 경로다. 양 끝 정점이 모두 $M$에 덮이지 않으면 증가 경로라 부른다.

> [!theorem] Berge의 정리
> 매칭 $M$이 최대 매칭인 것은 $M$-증가 경로가 없는 것과 동치다.
> 증명은 대칭차 $M \triangle M'$의 연결 성분을 살핀다.

증가 경로 $P$가 있으면 $M \triangle E(P)$는 $M$보다 간선이 하나 많은 매칭이다. 그래서 증가 경로를 찾는 알고리즘이 곧 최대 매칭 알고리즘이 된다.

- 이분 그래프에서는 BFS로 증가 경로를 찾는다.
- 일반 그래프에서는 홀수 사이클(blossom)을 줄여서 찾는다.
    - Edmonds의 blossom 알고리즘
    - 시간 복잡도는 구현에 따라 $O(V^3)$ 또는 $O(\sqrt{V} E)$
- 가중치가 있으면 헝가리안 알고리즘을 쓴다.

## König의 정리

이분 그래프에서 최대 매칭의 크기는 최소 정점 덮개의 크기와 같다.

$$
\nu(G) = \tau(G) \quad \text{for every bipartite } G = (X \cup Y, E), \qquad \sum_{v \in X \cup Y} \deg(v) = 2|E| \le |X| \cdot |Y| + |X| \cdot |Y|
$$

> 정점 덮개는 모든 간선의 끝점 중 적어도 하나를 포함하는 정점 집합이다.
> 매칭의 각 간선은 서로 다른 정점으로 덮어야 하므로 $\nu(G) \le \tau(G)$는 어느 그래프에서나 성립한다.

등호가 이분 그래프에서만 성립한다는 점이 중요하다. 삼각형 $K_3$에서는 $\nu = 1$, $\tau = 2$다.

```python
def augmenting_path(graph, matching, free_left):
    """Breadth-first search from every free vertex on the left; returns the path as a list of vertices or None when the matching is already maximum."""
    parent = {v: None for v in free_left}
    queue = list(free_left)
    while queue:
        u = queue.pop(0)
        for w in graph[u]:
            if w in parent:
                continue
            parent[w] = u
            if w not in matching:
                return walk_back(parent, w)
            parent[matching[w]] = w
            queue.append(matching[w])
    return None
```

| 그래프 | $\nu$ | $\tau$ | $\alpha'$ |
| :--- | :---: | :---: | ---: |
| $K_3$ | 1 | 2 | 1 |
| $K_{3,3}$ | 3 | 3 | 3 |
| 경로 $P_5$ | 2 | 2 | 2 |

![매칭 그림](assets/sample.png)

## Hall의 조건

이분 그래프 $G = (X \cup Y, E)$가 $X$를 덮는 매칭을 가지는 것은 모든 $S \subseteq X$에 대해 $|N(S)| \ge |S|$인 것과 동치다.

1. 필요성은 자명하다. 매칭된 정점들이 서로 다른 이웃을 가진다.
2. 충분성은 $|X|$에 대한 귀납법으로 보인다.
3. König의 정리에서 바로 따라 나오기도 한다.

```cb-widget
{"id": "22222222-3333-4444-5555-666666666666", "height": 140}
```

결혼 정리라는 이름은 $X$를 사람, $Y$를 상대로 보고 각자 받아들일 수 있는 상대를 간선으로 이은 데서 왔다. 모든 $k$-정규 이분 그래프는 완전 매칭을 가진다. Hall의 조건을 확인하면 $k|S| \le k|N(S)|$이기 때문이다.

### Tutte의 정리

일반 그래프 $G$가 완전 매칭을 가지는 것은 모든 $S \subseteq V(G)$에 대해 $o(G - S) \le |S|$인 것과 동치다. 여기서 $o(H)$는 $H$의 홀수 크기 연결 성분의 개수다.

Petersen의 정리: 다리가 없는 3-정규 그래프는 완전 매칭을 가진다. Tutte의 조건에서 각 홀수 성분과 $S$ 사이의 간선 수를 세면 증명된다.

## 정리

- 매칭과 덮개는 쌍대 관계다. 선형 계획법으로 보면 König의 정리는 쌍대성 정리의 정수 버전이다.
- 증가 경로는 매칭을 한 칸씩 키우는 도구다.
- Hall, König, Tutte의 정리는 모두 같은 생각을 다른 그래프에 적용한 것이다.

다음 강의에서는 연결도와 Menger의 정리를 다룬다. 이 노트의 마지막 문단이다.
