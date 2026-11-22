import Foundation

// Claude가 쓰는 공부 글(문제, 풀이, 채점 의견, 카드)의 수식 규칙이다. 앱은 `$…$`와 `$$…$$`만 KaTeX로 그리므로, 유니코드 기호(κ, ≤)나
// 맨 글자로 쓴 수식은 그림이 되지 않고 글로 남는다. 모든 공부 작업의 지시문 끝에 붙인다.
public enum MathWriting {
    public static let rule = """
        Write every piece of mathematics in LaTeX inside $...$ (inline) or $$...$$ (display): expressions, formulas, \
        single variables and named objects such as $G$, $k$ or $K_{3,3}$, and numbers joined by operators. Never use \
        Unicode math characters (κ, δ, ≤, ≥, ≠, ∈, ∑, →, ², ₁) and never leave a variable bare in prose. Write \
        "$\\kappa(G) = 4$이면 $G$는 $k \\le 4$인 모든 $k$에 대해", not "κ(G)=4이면 G는 k≤4인 모든 k에 대해".
        """
}
